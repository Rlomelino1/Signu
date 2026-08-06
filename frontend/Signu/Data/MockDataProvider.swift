import Foundation

/// In-memory provider with the mockups' dataset. "Today" is pinned to the
/// mockups' Sunday, Jul 13 2026 so previews are deterministic.
///
/// Dataset: 10 subscriptions (8 active — 6 monthly incl. 1 overdue, 2 annual;
/// 2 inactive — 1 ended, 1 cancelled), 2 possible-run suggestions, 2 dismissed,
/// 3 connections (active / needs action / expiring consent).
final class MockDataProvider: SignuDataProviding {
    /// Preview scenarios: the same provider drives every home-screen state.
    enum Scenario {
        case standard        // full dataset (21i-class)
        case freshConnection // bank connected, nothing detected yet (21h)
        case noBank          // nothing connected (21g)
    }

    let today = MockDataProvider.date(2026, 7, 13)
    /// Wall-clock "now" for relative copy ("Updated 2h ago", greeting).
    let now = MockDataProvider.dateTime(2026, 7, 13, 15, 35)

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
        case .noBank:
            connectionList = []
            accountList = []
            subscriptionList = []
            runList = []
            chargeList = []
            transactionAccountMap = [:]
        }
    }

    init() {
        profileValue = Profile(
            id: UUID(),
            displayName: "Rafael Souza",
            email: "rafael.souza@example.com",
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

    // MARK: - Home payload (endpoint stand-in)

    func homePayload() async throws -> HomePayload {
        HomePayload(
            firstName: firstName,
            now: now,
            banner: connectionBanner,
            content: homeContent
        )
    }

    private var firstName: String {
        profileValue.displayName.split(separator: " ").first.map(String.init) ?? profileValue.displayName
    }

    private var connectionBanner: HomePayload.Banner? {
        let troubled = connectionList.filter { $0.status == .needsAction || $0.status == .expired }
        guard let first = troubled.first else { return nil }
        let text = troubled.count == 1
            ? "\(first.institutionName) connection needs attention"
            : "\(troubled.count) bank connections need attention"
        return HomePayload.Banner(connectionId: first.id, text: text)
    }

    private var homeContent: HomePayload.Content {
        if connectionList.isEmpty { return .noBank }

        let visibleRuns = runList.filter { run in
            guard let sub = subscription(run.subscriptionId) else { return false }
            return !sub.ignored
        }
        guard visibleRuns.contains(where: { $0.status != .possible }) else {
            let bank = connectionList.first?.institutionName ?? ""
            return .watching(syncText: "Updated \(SignuFormat.ago(lastSynced ?? now, now: now)) · \(bank) connected")
        }

        // Hero: landed charges this calendar month, non-ignored subs,
        // primary currency only. Delta: same day-span of the previous month.
        let monthStart = Self.calendar.date(from: Self.calendar.dateComponents([.year, .month], from: today))!
        let previousMonthStart = Self.calendar.date(byAdding: .month, value: -1, to: monthStart)!
        let daysIntoMonth = Self.calendar.dateComponents([.day], from: monthStart, to: today).day!
        let previousSpanEnd = Self.calendar.date(byAdding: .day, value: daysIntoMonth, to: previousMonthStart)!

        let total = landedSum(from: monthStart, through: today)
        let previousTotal = landedSum(from: previousMonthStart, through: previousSpanEnd)
        let delta = total - previousTotal

        let activeRuns = visibleRuns.filter { $0.status == .active }
        let overdueRuns = visibleRuns.filter { $0.status == .overdue }
            .sorted { ($0.nextExpectedDate ?? today) < ($1.nextExpectedDate ?? today) }

        let horizon = Self.calendar.date(byAdding: .day, value: 14, to: today)!
        let comingUp = activeRuns
            .compactMap { run -> HomePayload.ComingUpItem? in
                guard let next = run.nextExpectedDate, next <= horizon, next >= today,
                      let sub = subscription(run.subscriptionId),
                      let last = latestCharge(run.id) else { return nil }
                return HomePayload.ComingUpItem(
                    id: run.id, subscriptionId: sub.id, serviceName: sub.displayName,
                    date: next, daysAway: days(from: today, to: next),
                    amount: last.amount, approximate: run.detectedBy.isApproximate
                )
            }
            .sorted { $0.date < $1.date }

        let overdue = overdueRuns.compactMap { run -> HomePayload.OverdueItem? in
            guard let expected = run.nextExpectedDate,
                  let sub = subscription(run.subscriptionId),
                  let last = latestCharge(run.id) else { return nil }
            return HomePayload.OverdueItem(
                id: run.id, subscriptionId: sub.id, serviceName: sub.displayName,
                expectedDate: expected, daysOverdue: days(from: expected, to: today),
                amount: last.amount, approximate: run.detectedBy.isApproximate
            )
        }

        let subscriptions = (activeRuns + overdueRuns)
            .compactMap { run -> HomePayload.SubscriptionItem? in
                guard let sub = subscription(run.subscriptionId),
                      let next = run.nextExpectedDate,
                      let last = latestCharge(run.id) else { return nil }
                let interval = run.billingInterval == .monthly ? "Monthly" : "Annual"
                return HomePayload.SubscriptionItem(
                    id: sub.id, serviceName: sub.displayName,
                    subtitle: "\(interval) · \(last.cardLabel)",
                    amount: last.amount, approximate: run.detectedBy.isApproximate,
                    nextDate: next,
                    overdueDays: run.status == .overdue ? days(from: next, to: today) : nil
                )
            }
            .sorted { $0.nextDate < $1.nextDate }

        let suggestionCount = visibleRuns.filter { $0.status == .possible }.count

        return .active(HomePayload.Active(
            monthToDateTotal: total,
            activeCount: activeRuns.count,
            overdueCount: overdueRuns.count,
            deltaVsPreviousMonth: delta == 0 ? nil : delta,
            previousMonthAbbrev: SignuFormat.monthAbbrev(previousMonthStart),
            syncText: "Updated \(SignuFormat.ago(lastSynced ?? now, now: now))",
            overdue: overdue,
            comingUp: comingUp,
            suggestionCount: suggestionCount,
            subscriptions: subscriptions
        ))
    }

    // MARK: - Subs payload (endpoint stand-in)

    func subsPayload() async throws -> SubsPayload {
        let visibleSubs = subscriptionList.filter { !$0.ignored }

        var monthlyRows: [SubsPayload.Row] = []
        var annualRows: [SubsPayload.Row] = []
        var suggested: [SubsPayload.SuggestedItem] = []
        var inactive: [SubsPayload.InactiveItem] = []

        for sub in visibleSubs {
            guard let run = latestRun(sub.id), let last = latestCharge(run.id) else { continue }
            switch run.status {
            case .active, .overdue:
                guard let next = run.nextExpectedDate else { continue }
                let interval = run.billingInterval == .monthly ? "Monthly" : "Annual"
                let row = SubsPayload.Row(
                    id: sub.id, serviceName: sub.displayName,
                    subtitle: "\(interval) · \(last.cardLabel)",
                    amount: last.amount, approximate: run.detectedBy.isApproximate,
                    nextDate: next,
                    overdueDays: run.status == .overdue ? days(from: next, to: today) : nil,
                    share: 0
                )
                if run.billingInterval == .monthly { monthlyRows.append(row) } else { annualRows.append(row) }
            case .possible:
                suggested.append(SubsPayload.SuggestedItem(
                    id: run.id, subscriptionId: sub.id, serviceName: sub.displayName,
                    evidence: suggestionEvidence(run)
                ))
            case .ended, .cancelled:
                let unit = run.billingInterval == .monthly ? "/mo" : "/yr"
                // Context clause dropped: the date lives in the right-rail
                // "Paid through", the ended/cancelled distinction in the chip.
                let cancelled = run.status == .cancelled
                inactive.append(SubsPayload.InactiveItem(
                    id: sub.id, serviceName: sub.displayName,
                    statusText: "Was \(SignuFormat.brl(last.amount)) \(unit)",
                    paidThroughText: "Paid through \(run.endDate.map(SignuFormat.monthDay) ?? SignuFormat.dash)",
                    cancelled: cancelled
                ))
            }
        }

        monthlyRows.sort { $0.nextDate < $1.nextDate }
        annualRows.sort { $0.nextDate < $1.nextDate }

        let monthlySubtotal = monthlyRows.reduce(Decimal.zero) { $0 + $1.amount }
        let annualSubtotal = annualRows.reduce(Decimal.zero) { $0 + $1.amount }
        for index in monthlyRows.indices {
            monthlyRows[index].share = share(monthlyRows[index].amount, of: monthlySubtotal)
        }
        for index in annualRows.indices {
            annualRows[index].share = share(annualRows[index].amount, of: annualSubtotal)
        }

        let yearly = monthlySubtotal * 12 + annualSubtotal
        let approximate = monthlyRows.contains(where: \.approximate) || annualRows.contains(where: \.approximate)

        return SubsPayload(
            yearlyTotal: yearly,
            yearlyApproximate: approximate,
            monthlyCompanion: yearly / 12,
            allCount: monthlyRows.count + annualRows.count + inactive.count,
            activeCount: monthlyRows.count + annualRows.count,
            inactiveCount: inactive.count,
            suggested: suggested,
            monthly: SubsPayload.Group(
                subtotal: monthlySubtotal,
                approximate: monthlyRows.contains(where: \.approximate),
                unitSuffix: "/mo", rows: monthlyRows
            ),
            annual: SubsPayload.Group(
                subtotal: annualSubtotal,
                approximate: annualRows.contains(where: \.approximate),
                unitSuffix: "/yr", rows: annualRows
            ),
            inactive: inactive
        )
    }

    // MARK: - Review payload (9a — endpoint stand-in)

    func reviewPayload() async throws -> ReviewPayload {
        let suggestions = runList
            .filter { $0.status == .possible }
            .filter { run in subscription(run.subscriptionId).map { !$0.ignored } ?? false }
            .compactMap { run -> ReviewPayload.Suggestion? in
                guard let sub = subscription(run.subscriptionId),
                      let last = latestCharge(run.id),
                      let next = run.nextExpectedDate else { return nil }
                let charges = chargeList
                    .filter { $0.runId == run.id }
                    .sorted { $0.date > $1.date }
                    .map {
                        ReviewPayload.ChargeLine(
                            id: $0.id,
                            dateText: SignuFormat.weekdayMonthDay($0.date),
                            cardLabel: $0.cardLabel,
                            amount: $0.amount
                        )
                    }
                return ReviewPayload.Suggestion(
                    id: run.id, subscriptionId: sub.id, serviceName: sub.displayName,
                    evidence: reviewEvidence(run),
                    charges: charges,
                    renewsDate: next,
                    renewsAmount: last.amount,
                    asksIntervalOnTrack: run.detectedBy == .r4
                )
            }
        return ReviewPayload(suggestions: suggestions)
    }

    /// Full evidence headline (9a). R3 measured cadence + varying amounts;
    /// R4 is the catalog fast-path off a single charge.
    private func reviewEvidence(_ run: SubscriptionRun) -> String {
        let count = chargeList.filter { $0.runId == run.id }.count
        switch run.detectedBy {
        case .r3:
            let cadence = run.billingInterval == .monthly ? "monthly" : "annual"
            return "\(count) charges, \(cadence) cadence · amounts vary"
        case .r4:
            return "Known subscription service · \(count) charge\(count == 1 ? "" : "s")"
        case .r1:
            return "\(count) charges"
        }
    }

    /// Compressed evidence (9b): only what the engine measured. R3 states
    /// cadence + approximate amount; R4 states the catalog fact, no amount.
    private func suggestionEvidence(_ run: SubscriptionRun) -> String {
        let charges = chargeList.filter { $0.runId == run.id }
        switch run.detectedBy {
        case .r3:
            let looks = run.billingInterval == .monthly ? "looks monthly" : "looks annual"
            let latest = charges.max { $0.date < $1.date }?.amount ?? 0
            return "\(charges.count) charges · \(looks) · \(SignuFormat.brlWhole(latest, approximate: true))"
        case .r4:
            return "1 charge · known subscription service"
        case .r1:
            return "\(charges.count) charges"
        }
    }

    private func latestRun(_ subscriptionId: UUID) -> SubscriptionRun? {
        runList.filter { $0.subscriptionId == subscriptionId }.max { $0.startDate < $1.startDate }
    }

    private func share(_ amount: Decimal, of total: Decimal) -> Double {
        total == 0 ? 0 : ((amount / total) as NSDecimalNumber).doubleValue
    }

    /// Primary currency is derived, never stored: dominant across charges.
    private var primaryCurrency: String {
        let counts = Dictionary(grouping: chargeList, by: \.currency).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? "BRL"
    }

    private func landedSum(from start: Date, through end: Date) -> Decimal {
        let currency = primaryCurrency
        return chargeList.reduce(Decimal.zero) { sum, charge in
            guard charge.date >= start, charge.date <= end, charge.currency == currency,
                  let run = runList.first(where: { $0.id == charge.runId }),
                  let sub = subscription(run.subscriptionId), !sub.ignored else { return sum }
            return sum + charge.amount
        }
    }

    private func subscription(_ id: UUID) -> Subscription? {
        subscriptionList.first { $0.id == id }
    }

    private func latestCharge(_ runId: UUID) -> Charge? {
        chargeList.filter { $0.runId == runId }.max { $0.date < $1.date }
    }

    private var lastSynced: Date? {
        connectionList.compactMap(\.lastSyncedAt).max()
    }

    private func days(from: Date, to: Date) -> Int {
        Self.calendar.dateComponents([.day], from: from, to: to).day ?? 0
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
