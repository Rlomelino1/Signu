import Foundation

/// In-memory provider with the mockups' dataset. "Today" is pinned to the
/// mockups' Sunday, Jul 13 2026 so previews are deterministic.
///
/// Dataset: 10 subscriptions (8 active — 6 monthly incl. 1 overdue, 2 annual;
/// 2 inactive — 1 ended, 1 cancelled), 2 possible-run suggestions, 2 dismissed,
/// 3 connections (active / needs action / expiring consent).
final class MockDataProvider: SignuDataProviding {
    let today = MockDataProvider.date(2026, 7, 13)

    private(set) var profileValue: Profile!
    private(set) var connectionList: [Connection] = []
    private(set) var accountList: [BankAccount] = []
    private(set) var subscriptionList: [Subscription] = []
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

    // MARK: - Dataset

    init() {
        profileValue = Profile(
            id: UUID(),
            displayName: "Rafael Souza",
            email: "rafael.souza@gmail.com",
            providers: ["google", "email"],
            createdAt: Self.date(2025, 10, 4)
        )

        // Connections + cards
        let nubank = Connection(
            id: UUID(), institutionId: "nubank", institutionName: "Nubank",
            status: .active, consentExpiresAt: Self.date(2026, 12, 10),
            lastSyncedAt: Self.dateTime(2026, 7, 13, 13, 35), lastSyncError: nil,
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
            lastSyncedAt: Self.dateTime(2026, 7, 13, 6, 0), lastSyncError: nil,
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
            charges: monthlySeries(
                from: Self.date(2025, 2, 22), through: Self.date(2026, 6, 22),
                account: master7730, label: "Master 7730"
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
                account: visa4821, label: "Visa 4821"
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
            charges: [
                ChargeSpec(date: Self.date(2024, 11, 12), amount: Self.brl("99.90"), account: visa4821, label: "Visa 4821"),
                ChargeSpec(date: Self.date(2025, 11, 12), amount: Self.brl("99.90"), account: visa4821, label: "Visa 4821"),
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

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }()

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
