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

    // MARK: - Writes
    //
    // No `.eq("user_id", …)` here either, for the same reason the reads have none:
    // RLS scopes the UPDATE, and a client-side predicate would be a second, weaker
    // copy of a rule the database already enforces. A write aimed at someone else's
    // row does not fail — it matches nothing, which is the correct outcome and one
    // this code does not have to arrange.
    //
    // Both write only columns inside Migration #1's column-scoped UPDATE grant. A
    // write outside it is rejected by Postgres regardless of what is asked for
    // here, so the grant is the real boundary and this is merely aligned with it.

    func setReminder(subscriptionId: UUID, remindBeforeDays: Int?) async throws {
        // `.null`, not an omitted key: turning reminders off means writing NULL,
        // because the nullable column IS the switch (v5).
        let value: AnyJSON = remindBeforeDays.map { AnyJSON.integer($0) } ?? .null
        try await update(subscriptionId: subscriptionId, values: ["remind_before_days": value])
    }

    func setIgnored(subscriptionId: UUID, ignored: Bool) async throws {
        try await update(subscriptionId: subscriptionId, values: ["ignored": .bool(ignored)])
    }

    /// `[String: AnyJSON]` rather than a single concrete Swift type, because the
    /// columns genuinely differ: `remind_before_days` is a nullable int and
    /// `ignored` a boolean. An earlier draft typed the dictionary `[String: Int?]`
    /// so one type could carry both, which sends `{"ignored": 1}` for a boolean
    /// column. Checked against a real Postgres rather than assumed: that IS
    /// accepted and coerces to true, so this is fidelity rather than a bug fix —
    /// but the value sent should be the value meant, and the next column added
    /// this way may not coerce so kindly.
    ///
    /// `nonisolated`, like the fetches: `PostgrestResponse` is not Sendable, so
    /// awaiting `execute()` from a main-actor method sends it across an isolation
    /// boundary — an error under the Swift 6.1 compiler CI builds with, even though
    /// newer compilers' region analysis allows it.
    private nonisolated func execute(subscriptionId: UUID, values: [String: AnyJSON]) async throws {
        try await client
            .from("subscription")
            .update(values)
            .eq("id", value: subscriptionId.uuidString)
            .execute()
    }

    /// Invalidates the cache after a successful write, so the next screen reads the
    /// row rather than the copy loaded before the change. Deliberately NOT an
    /// optimistic local edit: two representations of one row is how a UI comes to
    /// disagree with the database, and the re-read costs one round trip on a screen
    /// the user has just navigated away from.
    private func update(subscriptionId: UUID, values: [String: AnyJSON]) async throws {
        try await execute(subscriptionId: subscriptionId, values: values)
        loaded = false
    }

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
            let txRows = try await fetchTransactions(ids: referenced)
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

    // Both fetches are `nonisolated`, and that is load-bearing rather than tidy.
    //
    // `PostgrestResponse` is not Sendable, so awaiting `execute()` from a
    // main-actor method sends it across an isolation boundary. Swift 6.1 — CI's
    // Xcode 16.4 — rejects that outright; newer compilers' region analysis happens
    // to allow it, which is exactly how this passed locally and failed on CI.
    // Running the call off the actor means only the decoded rows cross back, and
    // row structs are implicitly Sendable: every field is a UUID, String, Double,
    // Bool or Date.
    //
    // `client` is readable from here because `SupabaseClient` is itself Sendable
    // and the property is a `let`.

    nonisolated private func fetch<T: Decodable & Sendable>(_ table: String) async throws -> [T] {
        try await client.from(table).select().execute().value
    }

    /// Only the transactions actually referenced by a charge — see the call site.
    nonisolated private func fetchTransactions(ids: [UUID]) async throws -> [TransactionRow] {
        try await client
            .from("transaction")
            .select("id, account_id, currency, amount, amount_in_account_currency")
            .in("id", values: ids.map(\.uuidString))
            .execute()
            .value
    }

    // MARK: - Edge Function writes (v30)
    //
    // The four actions the client is not granted: confirming a suggestion,
    // marking a run cancelled, removing a bank link, deleting an account. Each is
    // one POST to a function that resolves the caller from the session JWT and
    // then writes with the service role.
    //
    // No user id is ever sent. The SDK attaches the access token to every
    // invocation, and the server reads identity from it — a `userId` in one of
    // these bodies would be a request to act on whoever the client named.
    //
    // Each invalidates the cache on success, exactly as the column writes do:
    // one representation of a row, re-read on the next screen.

    func confirmSuggestion(runId: UUID, billingInterval: BillingInterval?) async throws {
        struct Body: Encodable {
            let runId: String
            let billingInterval: String?
        }
        try await invoke("confirm-suggestion", body: Body(
            runId: runId.uuidString,
            billingInterval: billingInterval?.rawValue
        ))
    }

    func markCancelled(subscriptionId: UUID) async throws {
        struct Body: Encodable { let subscriptionId: String }
        try await invoke("cancel-subscription", body: Body(subscriptionId: subscriptionId.uuidString))
    }

    func removeConnection(connectionId: UUID, deleteHistory: Bool) async throws {
        struct Body: Encodable {
            let connectionId: String
            let deleteHistory: Bool
        }
        try await invoke("remove-connection", body: Body(
            connectionId: connectionId.uuidString,
            deleteHistory: deleteHistory
        ))
    }

    func deleteAccount() async throws {
        // The same word the sheet makes the user type, restated at the API
        // boundary so a stray or replayed POST is inert.
        struct Body: Encodable { let confirm: String }
        try await invoke("delete-account", body: Body(confirm: "DELETE"))
    }

    // MARK: - Connecting a bank

    func connectSession(connectionId: UUID?) async throws -> ConnectSession {
        struct Body: Encodable { let connectionId: String? }
        struct Reply: Decodable { let accessToken: String }
        let reply: Reply = try await request(
            "connect-token",
            body: Body(connectionId: connectionId?.uuidString)
        )
        return ConnectSession(accessToken: reply.accessToken)
    }

    func registerConnection(itemId: String) async throws {
        struct Body: Encodable { let itemId: String }
        // The reply carries the connection id and the first sync's outcome; the
        // app needs neither, because the screens re-read the graph the sync just
        // wrote. Invalidating the cache is what that costs.
        try await invoke("register-connection", body: Body(itemId: itemId))
    }

    private func invoke(_ name: String, body: some Encodable & Sendable) async throws {
        try await send(name, body: body)
        loaded = false
    }

    /// `nonisolated` for the same reason the fetches are: the response type is
    /// not Sendable, so awaiting it from a main-actor method sends it across an
    /// isolation boundary — accepted by newer compilers' region analysis and
    /// rejected outright by the Swift 6.1 that CI builds with.
    nonisolated private func send(_ name: String, body: some Encodable & Sendable) async throws {
        do {
            try await client.functions.invoke(name, options: .init(body: body))
        } catch let FunctionsError.httpError(code, data) {
            // The function answers `{"error": "…"}` and says something specific:
            // "R4 confirmation must state monthly or annual", "a possible run
            // cannot be cancelled". Surfacing the status code alone would throw
            // that away and leave a screen with nothing true to render.
            throw ProviderError.action(name: name, status: code, message: Self.serverMessage(data))
        }
    }

    /// Same call, for the one function whose answer the app needs. Deliberately
    /// does NOT invalidate the cache: minting a token changes nothing.
    nonisolated private func request<T: Decodable>(
        _ name: String,
        body: some Encodable & Sendable
    ) async throws -> T {
        do {
            return try await client.functions.invoke(name, options: .init(body: body))
        } catch let FunctionsError.httpError(code, data) {
            throw ProviderError.action(name: name, status: code, message: Self.serverMessage(data))
        }
    }

    nonisolated private static func serverMessage(_ data: Data) -> String? {
        struct Failure: Decodable { let error: String? }
        return (try? JSONDecoder().decode(Failure.self, from: data))?.error
    }

    enum ProviderError: LocalizedError {
        case noProfile
        case action(name: String, status: Int, message: String?)
        var errorDescription: String? {
            switch self {
            case .noProfile:
                return "Signed in, but no profile row for this account."
            case let .action(name, status, message):
                return message ?? "\(name) failed (HTTP \(status))."
            }
        }
    }
}
