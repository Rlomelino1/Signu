import Foundation
import Supabase

/// Live `SignuDataProviding`, reading the interpreted chain through PostgREST.
///
/// It computes **no** payloads of its own. Conforming to `SignuPayloadSource`
/// gives it every screen payload from the same code the mock uses, so a screen
/// contract has one implementation and cannot drift between preview and
/// production — the reason that assembly was extracted first.
///
/// So this file is only two things: fetch and map. Nothing here decides what a
/// screen shows.
///
/// RLS does the scoping. Every table is readable by `authenticated` with a
/// `user_id` predicate (Migration #1), so these queries carry no `.eq("user_id",
/// …)` filter — adding one would be a second, weaker copy of a rule the database
/// already enforces, and one that silently disagrees if the policy changes.
@MainActor
final class SupabaseDataProvider: SignuDataProviding, SignuPayloadSource {

    private let client: SupabaseClient
    private var loaded = false

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    // MARK: - SignuPayloadSource
    //
    // Real clock, unlike the mock's pinned date. `today` is date-granular in the
    // São Paulo calendar, matching what the backend engine reasoned about: sync
    // converts Pluggy's UTC timestamps to São Paulo dates before truncating (v22),
    // so comparing against a UTC "today" here would put ~14% of rows a day out.

    var today: Date {
        let cal = SignuCalendar.saoPaulo
        return cal.date(from: cal.dateComponents([.year, .month, .day], from: Date()))!
    }
    var now: Date { Date() }

    private(set) var profileValue: Profile!
    private(set) var connectionList: [Connection] = []
    private(set) var accountList: [BankAccount] = []
    private(set) var subscriptionList: [Subscription] = []
    private(set) var runList: [SubscriptionRun] = []
    private(set) var chargeList: [Charge] = []
    private(set) var transactionAccountMap: [UUID: UUID] = [:]

    // MARK: - SignuDataProviding

    func profile() async throws -> Profile { try await ensureLoaded(); return profileValue }
    func connections() async throws -> [Connection] { try await ensureLoaded(); return connectionList }
    func bankAccounts() async throws -> [BankAccount] { try await ensureLoaded(); return accountList }
    func subscriptions() async throws -> [Subscription] { try await ensureLoaded(); return subscriptionList }

    func runs(subscriptionId: UUID) async throws -> [SubscriptionRun] {
        try await ensureLoaded()
        return runList.filter { $0.subscriptionId == subscriptionId }
    }

    func charges(runId: UUID) async throws -> [Charge] {
        try await ensureLoaded()
        return chargeList.filter { $0.runId == runId }.sorted { $0.date > $1.date }
    }

    func homePayload() async throws -> HomePayload { try await ensureLoaded(); return makeHomePayload() }
    func subsPayload() async throws -> SubsPayload { try await ensureLoaded(); return makeSubsPayload() }
    func reviewPayload() async throws -> ReviewPayload { try await ensureLoaded(); return makeReviewPayload() }

    func detailPayload(subscriptionId: UUID) async throws -> DetailPayload? {
        try await ensureLoaded()
        return makeDetailPayload(subscriptionId: subscriptionId)
    }

    func settingsPayload() async throws -> SettingsPayload { try await ensureLoaded(); return makeSettingsPayload() }

    func connectionDetailPayload(connectionId: UUID) async throws -> ConnectionDetailPayload? {
        try await ensureLoaded()
        return makeConnectionDetailPayload(connectionId: connectionId)
    }

    func attributedSubsPayload(connectionId: UUID) async throws -> AttributedSubsPayload? {
        try await ensureLoaded()
        return makeAttributedSubsPayload(connectionId: connectionId)
    }

    func deleteAccountScope() async throws -> DeleteAccountScope {
        try await ensureLoaded()
        return makeDeleteAccountScope()
    }

    // MARK: - Loading

    /// Payload assembly is synchronous over stored properties, so the whole
    /// working set is fetched once and held. That is also correct for the domain:
    /// every screen reads the same small graph, and per-screen fetching would make
    /// two screens disagree mid-session.
    private func ensureLoaded() async throws {
        guard !loaded else { return }
        try await reload()
    }

    /// Re-fetch everything. Public so a pull-to-refresh, or a sign-in, can discard
    /// a previous user's graph rather than merging into it.
    func reload() async throws {
        async let profileRows: [ProfileRow] = fetch("profiles")
        async let connectionRows: [ConnectionRow] = fetch("connection")
        async let accountRows: [BankAccountRow] = fetch("bank_account")
        async let subscriptionRows: [SubscriptionRow] = fetch("subscription")
        async let runRows: [RunRow] = fetch("subscription_run")
        async let chargeRows: [ChargeRow] = fetch("charge")

        let (profiles, connections, accounts, subs, runs, charges) =
            try await (profileRows, connectionRows, accountRows, subscriptionRows, runRows, chargeRows)

        let user = client.auth.currentUser
        guard let row = profiles.first else {
            // The signup trigger creates this row, so its absence means the
            // session does not match any profile — surfaced rather than papered
            // over with a placeholder that would render as a real account.
            throw ProviderError.noProfile
        }

        profileValue = Profile(
            id: row.id,
            displayName: row.displayName ?? user?.email ?? "",
            // Email and identity providers live in auth.users, never in profiles
            // — the schema says the reminder address is derived, not stored.
            email: user?.email ?? "",
            providers: user?.identities?.map(\.provider) ?? [],
            reminderChannels: ReminderChannels(rawValue: row.reminderChannels) ?? .email,
            createdAt: row.createdAt
        )

        connectionList = connections.map(\.domain)
        accountList = accounts.map(\.domain)
        subscriptionList = subs.map(\.domain)
        runList = runs.map(\.domain)

        let accountCurrencies = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0.currency) }
        )
        chargeList = charges.map { $0.domain(accountCurrency: nil) }

        // charge.transaction_id → bank_account.id, for bank attribution. Fetched
        // only for the transactions actually referenced, not the whole raw chain:
        // one account can hold hundreds of rows and the client needs none of them.
        let referenced = charges.compactMap(\.transactionId)
        if referenced.isEmpty {
            transactionAccountMap = [:]
        } else {
            let txRows: [TransactionRow] = try await client
                .from("transaction")
                .select("id, account_id, currency, amount, amount_in_account_currency")
                .in("id", values: referenced.map(\.uuidString))
                .execute()
                .value
            transactionAccountMap = Dictionary(
                uniqueKeysWithValues: txRows.map { ($0.id, $0.accountId) }
            )
            // Resolve each charge into its account's currency now that the owning
            // account is known. See Charge.amount for why this belongs here.
            let currencyByTx = Dictionary(uniqueKeysWithValues: txRows.map {
                ($0.id, accountCurrencies[$0.accountId] ?? nil)
            })
            chargeList = charges.map { charge in
                charge.domain(accountCurrency: charge.transactionId.flatMap { currencyByTx[$0] } ?? nil)
            }
        }

        loaded = true
    }

    private func fetch<T: Decodable>(_ table: String) async throws -> [T] {
        try await client.from(table).select().execute().value
    }

    enum ProviderError: LocalizedError {
        case noProfile
        var errorDescription: String? {
            switch self {
            case .noProfile:
                return "Signed in, but no profile row for this account."
            }
        }
    }
}
