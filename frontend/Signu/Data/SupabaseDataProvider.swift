import Foundation
import Supabase

@MainActor
final class SupabaseDataProvider: SignuDataProviding, SignuPayloadSource {

    private let client: SupabaseClient
    private var loaded = false

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }


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


    func setReminder(subscriptionId: UUID, remindBeforeDays: Int?) async throws {
        let value: AnyJSON = remindBeforeDays.map { AnyJSON.integer($0) } ?? .null
        try await update(subscriptionId: subscriptionId, values: ["remind_before_days": value])
    }

    func setIgnored(subscriptionId: UUID, ignored: Bool) async throws {
        try await update(subscriptionId: subscriptionId, values: ["ignored": .bool(ignored)])
    }

    func setNickname(subscriptionId: UUID, nickname: String?) async throws {
        let value: AnyJSON = nickname.map { AnyJSON.string($0) } ?? .null
        try await update(subscriptionId: subscriptionId, values: ["nickname": value])
    }


    func setDisplayName(_ name: String?) async throws {
        let value: AnyJSON = name.map { AnyJSON.string($0) } ?? .null
        try await updateProfile(values: ["display_name": value])
    }

    func setAvatar(jpeg: Data) async throws {
        guard let userId = client.auth.currentUser?.id else { throw ProviderError.noProfile }
        let path = "\(userId.uuidString.lowercased())/\(Int(Date().timeIntervalSince1970)).jpg"
        let previous = profileValue?.avatarPath

        try await upload(path: path, jpeg: jpeg)
        try await updateProfile(values: ["avatar_path": .string(path)])

        if let previous, previous != path {
            try? await removeObjects([previous])
        }
    }

    func removeAvatar() async throws {
        guard let path = profileValue?.avatarPath else { return }
        try await removeObjects([path])
        try await updateProfile(values: ["avatar_path": .null])
    }

    func avatarData(path: String) async throws -> Data {
        try await download(path: path)
    }

    private nonisolated func executeProfile(userId: UUID, values: [String: AnyJSON]) async throws {
        try await client
            .from("profiles")
            .update(values)
            .eq("id", value: userId.uuidString)
            .execute()
    }

    private nonisolated func upload(path: String, jpeg: Data) async throws {
        try await client.storage
            .from("avatars")
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
    }

    private nonisolated func removeObjects(_ paths: [String]) async throws {
        try await client.storage.from("avatars").remove(paths: paths)
    }

    private nonisolated func download(path: String) async throws -> Data {
        try await client.storage.from("avatars").download(path: path)
    }

    private func updateProfile(values: [String: AnyJSON]) async throws {
        guard let userId = client.auth.currentUser?.id else { throw ProviderError.noProfile }
        try await executeProfile(userId: userId, values: values)
        loaded = false
    }

    func setCategory(subscriptionId: UUID, category: String?) async throws {
        let value: AnyJSON = category.map { AnyJSON.string($0) } ?? .null
        try await update(subscriptionId: subscriptionId, values: ["category": value])
    }

    private nonisolated func execute(subscriptionId: UUID, values: [String: AnyJSON]) async throws {
        try await client
            .from("subscription")
            .update(values)
            .eq("id", value: subscriptionId.uuidString)
            .execute()
    }

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

    func brandCatalog() async throws -> [BrandCatalogEntry] {
        let rows: [BrandCatalogRow] = try await fetch("brand_catalog")
        return rows.map(\.domainModel)
    }

    func calendarPayload(monthContaining date: Date) async throws -> CalendarPayload {
        try await ensureLoaded()
        return makeCalendarPayload(monthContaining: date)
    }


    private func ensureLoaded() async throws {
        guard !loaded else { return }
        try await reload()
    }

    @discardableResult
    func refresh() async throws -> Bool {
        let before = graphSignature
        try await reload()
        return graphSignature != before
    }

    private var graphSignature: Int {
        GraphSignature.of(
            connections: connectionList,
            accounts: accountList,
            subscriptions: subscriptionList,
            runs: runList,
            charges: chargeList
        )
    }

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
            throw ProviderError.noProfile
        }

        let name = ProfileName.resolve(stored: row.displayName, email: user?.email ?? "")

        profileValue = Profile(
            id: row.id,
            displayName: name.display,
            displayNameIsFallback: name.isFallback,
            email: user?.email ?? "",
            providers: user?.identities?.map(\.provider) ?? [],
            reminderChannels: ReminderChannels(rawValue: row.reminderChannels) ?? .email,
            avatarPath: row.avatarPath,
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

        let referenced = charges.compactMap(\.transactionId)
        if referenced.isEmpty {
            transactionAccountMap = [:]
        } else {
            let txRows = try await fetchTransactions(ids: referenced)
            transactionAccountMap = Dictionary(
                uniqueKeysWithValues: txRows.map { ($0.id, $0.accountId) }
            )
            let currencyByTx = Dictionary(uniqueKeysWithValues: txRows.map {
                ($0.id, accountCurrencies[$0.accountId] ?? nil)
            })
            chargeList = charges.map { charge in
                charge.domain(accountCurrency: charge.transactionId.flatMap { currencyByTx[$0] } ?? nil)
            }
        }

        loaded = true
    }


    nonisolated private func fetch<T: Decodable & Sendable>(_ table: String) async throws -> [T] {
        try await client.from(table).select().execute().value
    }

    nonisolated private func fetchTransactions(ids: [UUID]) async throws -> [TransactionRow] {
        try await client
            .from("transaction")
            .select("id, account_id, currency, amount, amount_in_account_currency")
            .in("id", values: ids.map(\.uuidString))
            .execute()
            .value
    }


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
        struct Body: Encodable { let confirm: String }
        try await invoke("delete-account", body: Body(confirm: "DELETE"))
    }


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
        try await invoke("register-connection", body: Body(itemId: itemId))
    }

    private func invoke(_ name: String, body: some Encodable & Sendable) async throws {
        try await send(name, body: body)
        loaded = false
    }

    nonisolated private func send(_ name: String, body: some Encodable & Sendable) async throws {
        do {
            try await client.functions.invoke(name, options: .init(body: body))
        } catch let FunctionsError.httpError(code, data) {
            throw ProviderError.action(name: name, status: code, message: Self.serverMessage(data))
        }
    }

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
