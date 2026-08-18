import Foundation

/// In-memory provider with the mockups' dataset. "Today" is pinned to the
/// mockups' Sunday, Jul 13 2026 so previews are deterministic.
///
/// Dataset: 10 subscriptions (8 active — 6 monthly incl. 1 overdue, 2 annual;
/// 2 inactive — 1 ended, 1 cancelled), 2 possible-run suggestions, 2 dismissed,
/// 3 connections (active / needs action / expiring consent).
@MainActor
final class MockDataProvider: SignuDataProviding, SignuPayloadSource {
    /// Preview scenarios: the same provider drives every home-screen state.
    enum Scenario {
        case standard        // full dataset (21i-class)
        case freshConnection // bank connected, nothing detected yet (21h)
        case suggestionsOnly // connected, suggestions but nothing confirmed (22a)
        case noBank          // nothing connected (21g)
    }

    let today = MockDataProvider.date(2026, 7, 13)
    /// Wall-clock "now" for relative copy ("Updated 2h ago", greeting).
    let now = MockDataProvider.dateTime(2026, 7, 13, 15, 35)

    private(set) var profileValue: Profile!
    private(set) var connectionList: [Connection] = []
    private(set) var accountList: [BankAccount] = []
    // Not `private(set)`: the write methods below mutate it.
    var subscriptionList: [Subscription] = []
    private(set) var runList: [SubscriptionRun] = []
    private(set) var chargeList: [Charge] = []
    /// charge.transactionId → bank_account.id. Stands in for the raw
    /// transaction chain the mock layer doesn't model; powers the card row
    /// and the "found via this bank" attribution rule later.
    private(set) var transactionAccountMap: [UUID: UUID] = [:]

    // MARK: - SignuDataProviding

    func profile() async throws -> Profile { profileValue }
    func connections() async throws -> [Connection] { connectionList }
    func bankAccounts() async throws -> [BankAccount] { accountList }
    func subscriptions() async throws -> [Subscription] { subscriptionList }
    func runs(subscriptionId: UUID) async throws -> [SubscriptionRun] {
        runList.filter { $0.subscriptionId == subscriptionId }
    }
    func charges(runId: UUID) async throws -> [Charge] {
        chargeList.filter { $0.runId == runId }.sorted { $0.date > $1.date }
    }


    // MARK: - SignuDataProviding payloads
    //
    // Thin wrappers only. Every one delegates to the shared assembly in
    // PayloadSource.swift, which the live provider uses too — so a screen contract
    // is implemented exactly once.

    func homePayload() async throws -> HomePayload { makeHomePayload() }
    func subsPayload() async throws -> SubsPayload { makeSubsPayload() }
    func reviewPayload() async throws -> ReviewPayload { makeReviewPayload() }
    func detailPayload(subscriptionId: UUID) async throws -> DetailPayload? {
        makeDetailPayload(subscriptionId: subscriptionId)
    }
    func settingsPayload() async throws -> SettingsPayload { makeSettingsPayload() }

    // MARK: - Writes
    //
    // Mutates the in-memory fixtures rather than no-opping, so a preview or a
    // screenshot run behaves like the real thing: dismiss a suggestion and it
    // leaves review, restore it and it comes back. A mock that accepted writes and
    // discarded them would make every UI test of a write vacuously pass.

    func setReminder(subscriptionId: UUID, remindBeforeDays: Int?) async throws {
        guard let i = subscriptionList.firstIndex(where: { $0.id == subscriptionId }) else { return }
        subscriptionList[i].remindBeforeDays = remindBeforeDays
    }

    func setIgnored(subscriptionId: UUID, ignored: Bool) async throws {
        guard let i = subscriptionList.firstIndex(where: { $0.id == subscriptionId }) else { return }
        subscriptionList[i].ignored = ignored
    }

    func setNickname(subscriptionId: UUID, nickname: String?) async throws {
        guard let i = subscriptionList.firstIndex(where: { $0.id == subscriptionId }) else { return }
        subscriptionList[i].nickname = nickname
    }

    func setCategory(subscriptionId: UUID, category: String?) async throws {
        guard let i = subscriptionList.firstIndex(where: { $0.id == subscriptionId }) else { return }
        subscriptionList[i].category = category
    }

    // MARK: - Profile (v47)

    /// The avatar bytes the mock is standing in for storage with. Keyed by path so
    /// the fixture behaves like the bucket does: a new upload is a new key, and the
    /// old one stops being reachable.
    private var avatarObjects: [String: Data] = [:]

    func setDisplayName(_ name: String?) async throws {
        // Mirrors the live read through the same resolver, so the mock cannot
        // disagree with production about what counts as "no name" — which is
        // exactly how v47's null-check passed every test and failed in the app.
        let resolved = ProfileName.resolve(stored: name, email: profileValue.email)
        profileValue.displayName = resolved.display
        profileValue.displayNameIsFallback = resolved.isFallback
    }

    func setAvatar(jpeg: Data) async throws {
        let path = "\(profileValue.id.uuidString.lowercased())/\(Int(Date().timeIntervalSince1970)).jpg"
        let previous = profileValue.avatarPath
        avatarObjects[path] = jpeg
        profileValue.avatarPath = path
        if let previous, previous != path { avatarObjects[previous] = nil }
    }

    func removeAvatar() async throws {
        if let path = profileValue.avatarPath { avatarObjects[path] = nil }
        profileValue.avatarPath = nil
    }

    func avatarData(path: String) async throws -> Data {
        // Throws rather than returning empty for a path that is not there, because
        // the real bucket 404s and a store that treats "missing" as "zero bytes"
        // would cache the emptiness.
        guard let data = avatarObjects[path] else { throw MockError.noSuchAvatar }
        return data
    }

    enum MockError: Error { case noSuchAvatar }

    // MARK: - Edge Function writes, simulated (v30)
    //
    // Each mirrors what the function on the other side actually does, including
    // the parts that are easy to skip: confirmation leaves a `user_renamed`
    // subscription's identification alone, cancellation derives paid-through from
    // the last charge rather than from today, and removing a link with history
    // kept NULLs the surviving charges' transaction ids instead of deleting them.
    //
    // A mock that accepted these and did nothing would make every UI test of them
    // vacuously pass — the exact failure mode the write section above was written
    // against.

    func confirmSuggestion(runId: UUID, billingInterval: BillingInterval?) async throws {
        guard let r = runList.firstIndex(where: { $0.id == runId }) else { return }
        runList[r].status = .active
        if let billingInterval { runList[r].billingInterval = billingInterval }

        guard let s = subscriptionList.firstIndex(where: { $0.id == runList[r].subscriptionId }) else { return }
        // `user_renamed` is the stronger assertion and freezes the name; only
        // `auto` is promoted.
        if subscriptionList[s].identification == .auto {
            subscriptionList[s].identification = .userConfirmed
        }
    }

    func markCancelled(subscriptionId: UUID) async throws {
        let runs = runList.filter { $0.subscriptionId == subscriptionId }
        guard let latest = runs.max(by: { $0.startDate < $1.startDate }),
              let r = runList.firstIndex(where: { $0.id == latest.id }),
              latest.status == .active || latest.status == .overdue
        else { return }

        let lastCharge = chargeList.filter { $0.runId == latest.id }.map(\.date).max()
        let paidFrom = lastCharge ?? latest.startDate
        let months = latest.billingInterval == .annual ? 12 : 1

        runList[r].status = .cancelled
        runList[r].cancelledDate = today
        runList[r].endDate = Self.calendar.date(byAdding: .month, value: months, to: paidFrom)
        runList[r].nextExpectedDate = nil
    }

    func removeConnection(connectionId: UUID, deleteHistory: Bool) async throws {
        // Attribution comes from the payload the screens render, so the mock
        // cannot disagree with the count the sheet just showed the user.
        let payload = makeAttributedSubsPayload(connectionId: connectionId)
        let attributed = Set(
            (payload?.cardGroups.flatMap(\.rows).map(\.id) ?? []) + (payload?.dismissed.map(\.id) ?? [])
        )
        let accountIds = Set(accountList.filter { $0.connectionId == connectionId }.map(\.id))
        let transactions = Set(transactionAccountMap.filter { accountIds.contains($0.value) }.keys)

        if deleteHistory {
            let runIds = Set(runList.filter { attributed.contains($0.subscriptionId) }.map(\.id))
            chargeList.removeAll { runIds.contains($0.runId) }
            runList.removeAll { attributed.contains($0.subscriptionId) }
            subscriptionList.removeAll { attributed.contains($0.id) }
        }

        // ON DELETE SET NULL, by hand. Charges that outlive their transactions
        // stay self-describing through the duplicated date, amount and card
        // label — which is what makes "keep their history" mean anything.
        for i in chargeList.indices where chargeList[i].transactionId.map(transactions.contains) == true {
            chargeList[i].transactionId = nil
        }
        for tx in transactions { transactionAccountMap[tx] = nil }

        accountList.removeAll { $0.connectionId == connectionId }
        connectionList.removeAll { $0.id == connectionId }
    }

    // MARK: - Connecting a bank, simulated
    //
    // There is no widget to run here — Pluggy Connect needs a real token and a
    // real bank. So the session is flagged `simulated` and the flow renders a
    // labelled stand-in with a "Simulate success" button. That keeps the wiring
    // exercisable in previews and UI tests, and keeps the mock honest: it never
    // pretends a link it invented is a real one.

    func connectSession(connectionId: UUID?) async throws -> ConnectSession {
        ConnectSession(accessToken: "mock-connect-token", simulated: true)
    }

    func registerConnection(itemId: String) async throws {
        // Idempotent on the item id, like the UNIQUE (user_id,
        // provider_connection_id) the real path relies on.
        guard !connectionList.contains(where: { $0.institutionName == "Simulated Bank" }) else { return }
        let connection = Connection(
            id: UUID(),
            institutionId: "999",
            institutionName: "Simulated Bank",
            status: .active,
            consentExpiresAt: Self.calendar.date(byAdding: .month, value: 6, to: today),
            lastSyncedAt: now,
            lastSyncError: nil,
            createdAt: today
        )
        connectionList.append(connection)
        accountList.append(
            BankAccount(
                id: UUID(),
                connectionId: connection.id,
                type: .creditCard,
                brand: "Visa",
                last4: "0000",
                officialName: "Simulated card",
                nickname: nil,
                status: .active
            )
        )
    }

    func deleteAccount() async throws {
        // The cascade, locally: everything the account owns. `profileValue` is
        // deliberately left standing — the sheet's caller signs out immediately
        // after, and a nil profile would crash the screens on the way out.
        connectionList = []
        accountList = []
        subscriptionList = []
        runList = []
        chargeList = []
        transactionAccountMap = [:]
    }
    func connectionDetailPayload(connectionId: UUID) async throws -> ConnectionDetailPayload? {
        makeConnectionDetailPayload(connectionId: connectionId)
    }
    func attributedSubsPayload(connectionId: UUID) async throws -> AttributedSubsPayload? {
        makeAttributedSubsPayload(connectionId: connectionId)
    }
    func deleteAccountScope() async throws -> DeleteAccountScope { makeDeleteAccountScope() }
    func calendarPayload(monthContaining date: Date) async throws -> CalendarPayload {
        makeCalendarPayload(monthContaining: date)
    }

    /// A handful of entries, deliberately including services the fixtures do NOT
    /// subscribe to. The catalog is reference data about the world, and a mock
    /// that only listed the user's own merchants would quietly model the one
    /// shape the real thing must never have.
    func brandCatalog() async throws -> [BrandCatalogEntry] {
        [
            BrandCatalogEntry(id: UUID(), brandName: "Netflix", domain: "netflix.com",
                                 category: "Streaming", subscriptionOnly: true, kind: .service, patterns: ["netflix"]),
            BrandCatalogEntry(id: UUID(), brandName: "Spotify", domain: "spotify.com",
                                 category: "Music", subscriptionOnly: true, kind: .service, patterns: ["spotify"]),
            BrandCatalogEntry(id: UUID(), brandName: "ChatGPT Plus", domain: "openai.com",
                                 category: "AI", subscriptionOnly: true, kind: .service, patterns: ["openai", "chatgpt"]),
            BrandCatalogEntry(id: UUID(), brandName: "iCloud+", domain: "icloud.com",
                                 category: "Storage", subscriptionOnly: true, kind: .service, patterns: ["icloud"]),
            BrandCatalogEntry(id: UUID(), brandName: "Disney+", domain: "disneyplus.com",
                                 category: "Streaming", subscriptionOnly: true, kind: .service, patterns: ["disney"]),
            BrandCatalogEntry(id: UUID(), brandName: "Duolingo", domain: "duolingo.com",
                                 category: "Learning", subscriptionOnly: true, kind: .service, patterns: ["duolingo"]),
            BrandCatalogEntry(id: UUID(), brandName: "Amazon Prime", domain: "amazon.com.br",
                                 category: "Shopping", subscriptionOnly: true, kind: .service, patterns: ["amazon prime"]),
            BrandCatalogEntry(id: UUID(), brandName: "Twitch", domain: "twitch.tv",
                                 category: "Gaming", subscriptionOnly: false, kind: .service,
                                 patterns: ["twitch"]),
            // Institutions (v58). The fixture banks, so a Debug run and every preview
            // show real bank marks rather than monograms.
            BrandCatalogEntry(id: UUID(), brandName: "Nubank", domain: "nubank.com.br",
                              category: "Bank", subscriptionOnly: false, kind: .institution,
                              patterns: ["nubank", "nu pagamentos"]),
            BrandCatalogEntry(id: UUID(), brandName: "Itaú", domain: "itau.com.br",
                              category: "Bank", subscriptionOnly: false, kind: .institution,
                              patterns: ["itau"]),
            BrandCatalogEntry(id: UUID(), brandName: "Bradesco", domain: "bradesco.com.br",
                              category: "Bank", subscriptionOnly: false, kind: .institution,
                              patterns: ["bradesco"]),
        ]
    }

    /// Always false: the fixtures are the source of truth and nothing writes to
    /// them from outside the app, so a refresh here genuinely finds nothing new.
    /// Saying so is what lets a preview exercise pull-to-refresh without the
    /// screen flickering through a rebuild it did not need.
    @discardableResult
    func refresh() async throws -> Bool { false }

    // MARK: - Dataset

    convenience init(scenario: Scenario) {
        self.init()
        switch scenario {
        case .standard:
            break
        case .freshConnection:
            connectionList = connectionList.filter { $0.institutionName == "Nubank" }
            if var nubank = connectionList.first {
                nubank.lastSyncedAt = Self.calendar.date(byAdding: .minute, value: -1, to: now)
                connectionList = [nubank]
            }
            accountList = accountList.filter { account in connectionList.contains { $0.id == account.connectionId } }
            subscriptionList = []
            runList = []
            chargeList = []
            transactionAccountMap = [:]
        case .suggestionsOnly:
            // The first-sync shape 22a is for: the engine found candidates and
            // auto-confirmed none of them, so every run is `possible`. The
            // fixtures already carry two such subscriptions; this drops
            // everything else, including the dismissed ones, so the count on
            // screen is the count under test.
            connectionList = connectionList.filter { $0.institutionName == "Nubank" }
            accountList = accountList.filter { account in connectionList.contains { $0.id == account.connectionId } }
            let suggested = Set(
                subscriptionList
                    .filter { sub in
                        !sub.ignored && runList.filter { $0.subscriptionId == sub.id }.allSatisfy { $0.status == .possible }
                    }
                    .map(\.id)
            )
            subscriptionList = subscriptionList.filter { suggested.contains($0.id) }
            runList = runList.filter { suggested.contains($0.subscriptionId) }
            let keptRuns = Set(runList.map(\.id))
            chargeList = chargeList.filter { keptRuns.contains($0.runId) }
        case .noBank:
            connectionList = []
            accountList = []
            subscriptionList = []
            runList = []
            chargeList = []
            transactionAccountMap = [:]
        }
    }

    private static var googleOnly: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--settings-google-only")
        #else
        false
        #endif
    }

    init() {
        profileValue = Profile(
            id: UUID(),
            displayName: "Rafael Souza",
            email: "rafael.souza@example.com",
            // Google-only is the interesting half of v19's password row ("Set a
            // password" plus its explanatory subtitle) and no scenario reaches it,
            // so a flag does — same harness pattern as --subs-inactive.
            providers: Self.googleOnly ? ["google"] : ["google", "email"],
            createdAt: Self.date(2025, 10, 4)
        )

        // Connections + cards
        let nubank = Connection(
            id: UUID(), institutionId: "nubank", institutionName: "Nubank",
            status: .active, consentExpiresAt: Self.date(2026, 12, 10),
            lastSyncedAt: Self.dateTime(2026, 7, 13, 13, 35),
            // Pluggy refreshed the item ~1.5h before our read, which is the ordinary
            // shape: our sync is scheduled AFTER the provider's auto-sync (v65).
            providerUpdatedAt: Self.dateTime(2026, 7, 13, 12, 1),
            lastSyncError: nil,
            createdAt: Self.date(2025, 11, 2)
        )
        let itau = Connection(
            id: UUID(), institutionId: "itau", institutionName: "Itaú",
            status: .needsAction, consentExpiresAt: Self.date(2026, 9, 28),
            lastSyncedAt: Self.dateTime(2026, 7, 12, 8, 14),
            lastSyncError: "The bank paused this connection on Jul 12.",
            createdAt: Self.date(2025, 10, 4)
        )
        let bradesco = Connection(
            id: UUID(), institutionId: "bradesco", institutionName: "Bradesco",
            status: .active, consentExpiresAt: Self.date(2026, 8, 2),
            lastSyncedAt: Self.dateTime(2026, 7, 13, 6, 0),
            // The case the label exists for: we read Pluggy this morning, but Pluggy
            // itself had not refreshed since the previous evening, so this
            // connection's data is ~7h older than "Synced 6:00" suggests.
            providerUpdatedAt: Self.dateTime(2026, 7, 12, 22, 54),
            lastSyncError: nil,
            createdAt: Self.date(2026, 1, 15)
        )
        connectionList = [nubank, itau, bradesco]

        let visa4821 = BankAccount(
            id: UUID(), connectionId: itau.id, type: .creditCard, brand: "Visa",
            last4: "4821", officialName: "Itaú Visa Platinum", nickname: nil, status: .active
        )
        let master7730 = BankAccount(
            id: UUID(), connectionId: itau.id, type: .creditCard, brand: "Mastercard",
            last4: "7730", officialName: "Itaú Mastercard Black", nickname: nil, status: .active
        )
        let nubankVisa = BankAccount(
            id: UUID(), connectionId: nubank.id, type: .creditCard, brand: "Visa",
            last4: "1029", officialName: "Nubank Visa", nickname: nil, status: .active
        )
        let nubankChecking = BankAccount(
            id: UUID(), connectionId: nubank.id, type: .checking, brand: nil,
            last4: "5566", officialName: "NuConta", nickname: nil, status: .active
        )
        let bradescoElo = BankAccount(
            id: UUID(), connectionId: bradesco.id, type: .creditCard, brand: "Elo",
            last4: "3311", officialName: "Bradesco Elo Nanquim", nickname: nil, status: .active
        )
        accountList = [visa4821, master7730, nubankVisa, nubankChecking, bradescoElo]

        // Active monthly (R1 unless noted)
        addSubscription(
            name: "Netflix", merchantKey: "netflix", category: "Streaming",
            createdAt: Self.date(2023, 11, 18),
            run: RunSpec(
                interval: .monthly, status: .active, detectedBy: .r1,
                start: Self.date(2023, 11, 18), nextExpected: Self.date(2026, 7, 18)
            ),
            charges: monthlySeries(
                from: Self.date(2023, 11, 18), through: Self.date(2026, 6, 18),
                account: visa4821, label: "Visa 4821"
            ) { $0 >= Self.date(2026, 3, 18) ? Self.brl("44.90") : Self.brl("39.90") }
        )
        addSubscription(
            name: "Spotify", merchantKey: "spotify", category: "Music",
            createdAt: Self.date(2024, 8, 15),
            run: RunSpec(
                interval: .monthly, status: .active, detectedBy: .r1,
                start: Self.date(2024, 8, 15), nextExpected: Self.date(2026, 7, 15)
            ),
            // Card hop: Visa 4821 through Apr 15, Master 7730 from May 15 (21n).
            charges: monthlySeries(
                from: Self.date(2024, 8, 15), through: Self.date(2026, 6, 15),
                account: { $0 >= Self.date(2026, 5, 15) ? master7730 : visa4821 },
                label: { $0 >= Self.date(2026, 5, 15) ? "Master 7730" : "Visa 4821" }
            ) { _ in Self.brl("21.90") }
        )
        addSubscription(
            name: "Globoplay", merchantKey: "globoplay", category: "Streaming",
            createdAt: Self.date(2025, 10, 10),
            run: RunSpec(
                interval: .monthly, status: .overdue, detectedBy: .r1,
                start: Self.date(2025, 10, 10), nextExpected: Self.date(2026, 7, 10)
            ),
            charges: monthlySeries(
                from: Self.date(2025, 10, 10), through: Self.date(2026, 6, 10),
                account: master7730, label: "Master 7730"
            ) { _ in Self.brl("24.90") }
        )
        addSubscription(
            name: "iCloud+", merchantKey: "apple:14.90", category: "Storage",
            createdAt: Self.date(2025, 2, 22),
            run: RunSpec(
                interval: .monthly, status: .active, detectedBy: .r1,
                start: Self.date(2025, 2, 22), nextExpected: Self.date(2026, 7, 22)
            ),
            // Billed on Nubank Visa (spreads subs across the 3 banks).
            charges: monthlySeries(
                from: Self.date(2025, 2, 22), through: Self.date(2026, 6, 22),
                account: nubankVisa, label: "Visa 1029"
            ) { _ in Self.brl("14.90") }
        )
        addSubscription(
            name: "Disney+", merchantKey: "disneyplus", category: "Streaming",
            createdAt: Self.date(2026, 1, 30),
            run: RunSpec(
                interval: .monthly, status: .active, detectedBy: .r1,
                start: Self.date(2026, 1, 30), nextExpected: Self.date(2026, 7, 30)
            ),
            charges: monthlySeries(
                from: Self.date(2026, 1, 30), through: Self.date(2026, 6, 30),
                account: nubankVisa, label: "Visa 1029"
            ) { _ in Self.brl("19.90") }
        )
        addSubscription(
            name: "Smart Fit", merchantKey: "smartfit", category: "Fitness",
            createdAt: Self.date(2025, 3, 2),
            run: RunSpec(
                interval: .monthly, status: .active, detectedBy: .r1,
                start: Self.date(2025, 3, 2), nextExpected: Self.date(2026, 8, 2)
            ),
            charges: monthlySeries(
                from: Self.date(2025, 3, 2), through: Self.date(2026, 7, 2),
                account: master7730, label: "Master 7730"
            ) { _ in Self.brl("119.90") }
        )

        // Active annual
        addSubscription(
            name: "Google One", merchantKey: "google one", category: "Storage",
            createdAt: Self.date(2024, 11, 12),
            run: RunSpec(
                interval: .annual, status: .active, detectedBy: .r1,
                start: Self.date(2024, 11, 12), nextExpected: Self.date(2026, 11, 12)
            ),
            // Billed on Bradesco Elo.
            charges: [
                ChargeSpec(date: Self.date(2024, 11, 12), amount: Self.brl("99.90"), account: bradescoElo, label: "Elo 3311"),
                ChargeSpec(date: Self.date(2025, 11, 12), amount: Self.brl("99.90"), account: bradescoElo, label: "Elo 3311"),
            ]
        )
        addSubscription(
            name: "Duolingo Super", merchantKey: "duolingo", category: "Education",
            createdAt: Self.date(2025, 2, 3),
            run: RunSpec(
                interval: .annual, status: .active, detectedBy: .r1,
                start: Self.date(2025, 2, 3), nextExpected: Self.date(2027, 2, 3)
            ),
            charges: [
                ChargeSpec(date: Self.date(2025, 2, 3), amount: Self.brl("349.00"), account: master7730, label: "Master 7730"),
                ChargeSpec(date: Self.date(2026, 2, 3), amount: Self.brl("349.00"), account: master7730, label: "Master 7730"),
            ]
        )

        // Inactive: engine-ended vs user-cancelled (8a's copy split)
        addSubscription(
            name: "Amazon Prime", merchantKey: "amazon prime", category: "Streaming",
            createdAt: Self.date(2024, 6, 18),
            run: RunSpec(
                interval: .monthly, status: .ended, detectedBy: .r1,
                start: Self.date(2024, 6, 18), end: Self.date(2026, 4, 18), nextExpected: nil
            ),
            charges: monthlySeries(
                from: Self.date(2024, 6, 18), through: Self.date(2026, 3, 18),
                account: visa4821, label: "Visa 4821"
            ) { _ in Self.brl("19.90") }
        )
        addSubscription(
            name: "MUBI", merchantKey: "mubi", category: "Streaming",
            createdAt: Self.date(2025, 9, 2),
            run: RunSpec(
                interval: .monthly, status: .cancelled, detectedBy: .r1,
                start: Self.date(2025, 9, 2), end: Self.date(2026, 8, 2),
                cancelled: Self.date(2026, 7, 2), nextExpected: nil
            ),
            charges: monthlySeries(
                from: Self.date(2025, 9, 2), through: Self.date(2026, 7, 2),
                account: visa4821, label: "Visa 4821"
            ) { _ in Self.brl("32.90") }
        )

        // Suggestions (possible runs — 9a/9b)
        addSubscription(
            name: "ChatGPT Plus", merchantKey: "openai", category: "AI",
            createdAt: Self.date(2026, 5, 7),
            run: RunSpec(
                interval: .monthly, status: .possible, detectedBy: .r3,
                start: Self.date(2026, 5, 7), nextExpected: Self.date(2026, 8, 7)
            ),
            charges: [
                ChargeSpec(date: Self.date(2026, 5, 7), amount: Self.brl("110.17"), account: visa4821, label: "Visa 4821"),
                ChargeSpec(date: Self.date(2026, 6, 7), amount: Self.brl("108.63"), account: visa4821, label: "Visa 4821"),
                ChargeSpec(date: Self.date(2026, 7, 7), amount: Self.brl("112.40"), account: visa4821, label: "Visa 4821"),
            ]
        )
        addSubscription(
            name: "Meli+", merchantKey: "meli", category: "Shopping",
            createdAt: Self.date(2026, 7, 5),
            run: RunSpec(
                interval: .monthly, status: .possible, detectedBy: .r4,
                start: Self.date(2026, 7, 5), nextExpected: Self.date(2026, 8, 5)
            ),
            charges: [
                ChargeSpec(date: Self.date(2026, 7, 5), amount: Self.brl("17.99"), account: master7730, label: "Master 7730"),
            ]
        )

        // Dismissed suggestions (ignored = true — 12a's restore surface)
        addSubscription(
            name: "Uber One", merchantKey: "uber one", category: "Transport",
            createdAt: Self.date(2026, 6, 14), ignored: true,
            run: RunSpec(
                interval: .monthly, status: .possible, detectedBy: .r4,
                start: Self.date(2026, 6, 12), nextExpected: Self.date(2026, 7, 12)
            ),
            charges: [
                ChargeSpec(date: Self.date(2026, 6, 12), amount: Self.brl("24.99"), account: visa4821, label: "Visa 4821"),
            ]
        )
        addSubscription(
            name: "Amazon", merchantKey: "amazon", category: "Shopping",
            createdAt: Self.date(2026, 5, 30), ignored: true,
            run: RunSpec(
                interval: .monthly, status: .possible, detectedBy: .r3,
                start: Self.date(2026, 3, 28), nextExpected: Self.date(2026, 6, 28)
            ),
            charges: [
                ChargeSpec(date: Self.date(2026, 3, 28), amount: Self.brl("67.40"), account: master7730, label: "Master 7730"),
                ChargeSpec(date: Self.date(2026, 4, 28), amount: Self.brl("81.15"), account: master7730, label: "Master 7730"),
                ChargeSpec(date: Self.date(2026, 5, 28), amount: Self.brl("54.02"), account: master7730, label: "Master 7730"),
            ]
        )
    }


    // MARK: - Builders

    private struct RunSpec {
        var interval: BillingInterval
        var status: RunStatus
        var detectedBy: DetectedBy
        var start: Date
        var end: Date?
        var cancelled: Date?
        var nextExpected: Date?

        init(interval: BillingInterval, status: RunStatus, detectedBy: DetectedBy,
             start: Date, end: Date? = nil, cancelled: Date? = nil, nextExpected: Date?) {
            self.interval = interval
            self.status = status
            self.detectedBy = detectedBy
            self.start = start
            self.end = end
            self.cancelled = cancelled
            self.nextExpected = nextExpected
        }
    }

    private struct ChargeSpec {
        var date: Date
        var amount: Decimal
        var account: BankAccount
        var label: String
    }

    private func addSubscription(
        name: String, merchantKey: String, category: String,
        createdAt: Date, ignored: Bool = false,
        run: RunSpec, charges: [ChargeSpec]
    ) {
        let subscription = Subscription(
            id: UUID(), serviceName: name, nickname: nil, merchantKey: merchantKey,
            category: category, identification: .auto, ignored: ignored,
            remindBeforeDays: nil, createdAt: createdAt
        )
        subscriptionList.append(subscription)
        let runId = UUID()
        runList.append(SubscriptionRun(
            id: runId, subscriptionId: subscription.id,
            startDate: run.start, endDate: run.end, cancelledDate: run.cancelled,
            billingInterval: run.interval, status: run.status,
            detectedBy: run.detectedBy, nextExpectedDate: run.nextExpected
        ))
        for spec in charges {
            let transactionId = UUID()
            transactionAccountMap[transactionId] = spec.account.id
            chargeList.append(Charge(
                id: UUID(), runId: runId, transactionId: transactionId,
                date: spec.date, amount: spec.amount, currency: "BRL", cardLabel: spec.label
            ))
        }
    }

    private func monthlySeries(
        from start: Date, through end: Date,
        account: @escaping (Date) -> BankAccount, label: @escaping (Date) -> String,
        amount: (Date) -> Decimal
    ) -> [ChargeSpec] {
        var specs: [ChargeSpec] = []
        var current = start
        while current <= end {
            specs.append(ChargeSpec(date: current, amount: amount(current), account: account(current), label: label(current)))
            current = Self.calendar.date(byAdding: .month, value: 1, to: current)!
        }
        return specs
    }

    private func monthlySeries(
        from start: Date, through end: Date,
        account: BankAccount, label: String,
        amount: (Date) -> Decimal
    ) -> [ChargeSpec] {
        monthlySeries(from: start, through: end, account: { _ in account }, label: { _ in label }, amount: amount)
    }

    // MARK: - Date/decimal helpers

    /// Defined once in `SignuCalendar` so the mock and the live provider cannot
    /// drift onto different calendars.
    static let calendar: Calendar = SignuCalendar.saoPaulo

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static func dateTime(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func brl(_ string: String) -> Decimal {
        Decimal(string: string)!
    }
}

// MARK: - Detail-screen fixture (21q)

extension MockDataProvider {
    /// Max — the run-segmentation demo (2 runs with a NOT SUBSCRIBED gap).
    /// Kept out of the main dataset so list counts stay at the mockups'
    /// All·10 / Active·8 / Inactive·2; detail previews use it directly.
    static func demoMax() -> (subscription: Subscription, runs: [SubscriptionRun], charges: [Charge]) {
        let subscription = Subscription(
            id: UUID(), serviceName: "Max", nickname: nil, merchantKey: "max",
            category: "Streaming", identification: .auto, ignored: false,
            remindBeforeDays: nil, createdAt: date(2025, 9, 5)
        )
        let run1Id = UUID()
        let run2Id = UUID()
        let runs = [
            SubscriptionRun(
                id: run1Id, subscriptionId: subscription.id,
                startDate: date(2025, 9, 5), endDate: date(2025, 11, 5), cancelledDate: nil,
                billingInterval: .monthly, status: .ended, detectedBy: .r1, nextExpectedDate: nil
            ),
            SubscriptionRun(
                id: run2Id, subscriptionId: subscription.id,
                startDate: date(2026, 5, 5), endDate: nil, cancelledDate: nil,
                billingInterval: .monthly, status: .active, detectedBy: .r1,
                nextExpectedDate: date(2026, 8, 5)
            ),
        ]
        let charges = [
            Charge(id: UUID(), runId: run1Id, transactionId: nil, date: date(2025, 9, 5),
                   amount: brl("29.90"), currency: "BRL", cardLabel: "Visa 4821"),
            Charge(id: UUID(), runId: run1Id, transactionId: nil, date: date(2025, 10, 5),
                   amount: brl("29.90"), currency: "BRL", cardLabel: "Visa 4821"),
            Charge(id: UUID(), runId: run2Id, transactionId: nil, date: date(2026, 5, 5),
                   amount: brl("34.90"), currency: "BRL", cardLabel: "Visa 4821"),
            Charge(id: UUID(), runId: run2Id, transactionId: nil, date: date(2026, 6, 5),
                   amount: brl("34.90"), currency: "BRL", cardLabel: "Visa 4821"),
            Charge(id: UUID(), runId: run2Id, transactionId: nil, date: date(2026, 7, 5),
                   amount: brl("34.90"), currency: "BRL", cardLabel: "Visa 4821"),
        ]
        return (subscription, runs, charges)
    }
}
