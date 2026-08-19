import Foundation

@MainActor
protocol SignuPayloadSource {
    var today: Date { get }
    var now: Date { get }
    var profileValue: Profile! { get }
    var connectionList: [Connection] { get }
    var accountList: [BankAccount] { get }
    var subscriptionList: [Subscription] { get }
    var runList: [SubscriptionRun] { get }
    var chargeList: [Charge] { get }
    var transactionAccountMap: [UUID: UUID] { get }
}

enum SignuCalendar {
    static let saoPaulo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }()
}

extension SignuPayloadSource {
    static var calendar: Calendar { SignuCalendar.saoPaulo }
}

extension SignuPayloadSource {

    func makeHomePayload() -> HomePayload {
        HomePayload(
            firstName: firstName,
            initial: profileInitial,
            avatarPath: profileValue.avatarPath,
            now: now,
            banner: connectionBanner,
            content: homeContent
        )
    }

    private var firstName: String? {
        guard !profileValue.displayNameIsFallback else { return nil }
        return profileValue.displayName.split(separator: " ").first.map(String.init)
            ?? profileValue.displayName
    }

    private var profileInitial: String {
        let source = firstName ?? profileValue.email
        return String(source.prefix(1)).uppercased()
    }

    private var connectionBanner: HomePayload.Banner? {
        let troubled = connectionList.filter { $0.status == .needsAction || $0.status == .expired }
        guard let first = troubled.first else { return nil }
        let text = troubled.count == 1
            ? "\(bankLabel(first)) connection needs attention"
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
            let bank = connectionList.first.map(bankLabel) ?? ""
            let names = visibleRuns
                .filter { $0.status == .possible }
                .compactMap { subscription($0.subscriptionId)?.displayName }
                .sorted()
            return .watching(HomePayload.Watching(
                headline: names.isEmpty ? "No subscriptions detected yet" : "No confirmed subscriptions yet",
                syncText: "Updated \(SignuFormat.ago(dataFreshAsOf ?? now, now: now)) · \(bank) connected",
                suggestionCount: names.count,
                suggestionLine: HomePayload.suggestionLine(names)
            ))
        }

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
                return HomePayload.SubscriptionItem(
                    id: sub.id, serviceName: sub.displayName,
                    subtitle: intervalAndCard(run, last),
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
            syncText: "Updated \(SignuFormat.ago(dataFreshAsOf ?? now, now: now))",
            overdue: overdue,
            comingUp: comingUp,
            suggestionCount: suggestionCount,
            subscriptions: subscriptions
        ))
    }


    func makeSubsPayload() -> SubsPayload {
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
                let row = SubsPayload.Row(
                    id: sub.id, serviceName: sub.displayName,
                    subtitle: intervalAndCard(run, last),
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


    func makeReviewPayload() -> ReviewPayload {
        let suggestions = runList
            .filter { $0.status == .possible }
            .filter { run in subscription(run.subscriptionId).map { !$0.ignored } ?? false }
            .compactMap { run -> ReviewPayload.Suggestion? in
                guard let sub = subscription(run.subscriptionId),
                      let last = latestCharge(run.id) else { return nil }
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
                    renewsDate: run.nextExpectedDate,
                    renewsAmount: last.amount,
                    asksIntervalOnTrack: run.detectedBy == .r4,
                    billingInterval: run.billingInterval
                )
            }
        return ReviewPayload(
            suggestions: suggestions,
            remindersNeverUsed: subscriptionList.allSatisfy { $0.remindBeforeDays == nil }
        )
    }

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

    func intervalAndCard(_ run: SubscriptionRun, _ charge: Charge) -> String {
        let interval = run.billingInterval == .monthly ? "Monthly" : "Annual"
        guard let card = derivedCardLabel(for: charge) else { return interval }
        return "\(interval) · \(card)"
    }

    func derivedCardLabel(for charge: Charge) -> String? {
        let stored = charge.cardLabel.trimmingCharacters(in: .whitespaces)
        if !stored.isEmpty { return stored }

        guard let transactionId = charge.transactionId,
              let accountId = transactionAccountMap[transactionId],
              let account = accountList.first(where: { $0.id == accountId })
        else { return nil }

        let brand = account.brand?.lowercased() == "mastercard"
            ? "Master"
            : account.brand.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        guard let brand, !account.last4.isEmpty else { return nil }
        return "\(brand) \(account.last4)"
    }

    private func subscription(_ id: UUID) -> Subscription? {
        subscriptionList.first { $0.id == id }
    }

    private func latestCharge(_ runId: UUID) -> Charge? {
        chargeList.filter { $0.runId == runId }.max { $0.date < $1.date }
    }

    private var dataFreshAsOf: Date? {
        connectionList.compactMap(\.dataFreshAsOf).min()
    }

    private func days(from: Date, to: Date) -> Int {
        Self.calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
