import Foundation

// Detail-screen timeline synthesis. Interleaves synthesized run-state events
// (renewal, cancellation, missed, ended, gap) with charge rows by date.
//
// Moved verbatim out of MockDataProvider+Detail.swift so the live provider
// shares it. See PayloadSource.swift for why.

extension SignuPayloadSource {
    func makeDetailPayload(subscriptionId: UUID) -> DetailPayload? {
        guard let sub = subscriptionList.first(where: { $0.id == subscriptionId }) else { return nil }
        let runs = runList.filter { $0.subscriptionId == sub.id }
        let charges = chargeList.filter { charge in runs.contains { $0.id == charge.runId } }
        return detailPayload(subscription: sub, runs: runs, charges: charges)
    }

    /// Pure builder — also used by the preview fixtures (demoMax, demoCancelled).
    func detailPayload(subscription sub: Subscription,
                       runs allRuns: [SubscriptionRun],
                       charges allCharges: [Charge]) -> DetailPayload {
        let cal = Self.calendar
        let refYear = cal.component(.year, from: today)
        let runs = allRuns.sorted { $0.startDate < $1.startDate }

        guard let latest = runs.last,
              let lastCharge = allCharges.filter({ $0.runId == latest.id }).max(by: { $0.date < $1.date })
        else {
            return DetailPayload(
                id: sub.id, serviceName: sub.displayName, subtitle: "", statusText: "",
                statusTone: .neutral, amountText: SignuFormat.dash, unit: "/mo",
                dateSlot: .paidThrough(SignuFormat.dash), thisYearText: SignuFormat.dash,
                sinceLabel: "", sinceTotalText: SignuFormat.dash, events: [],
                showRemindMe: false, reminderOn: false, showMarkCancelled: false, footer: nil
            )
        }

        let interval = latest.billingInterval
        let currentCard = lastCharge.cardLabel

        // MARK: Hero
        let unit = interval == .monthly ? "/mo" : "/yr"
        let approx = latest.detectedBy.isApproximate            // tilde iff R3/R4
        let amountText = SignuFormat.brl(lastCharge.amount, approximate: approx)
        let subtitle = "\(interval == .monthly ? "Monthly" : "Annual") · \(cardWithDash(currentCard))"

        let (statusText, statusTone) = statusChip(latest.status)
        let dateSlot = heroDateSlot(latest)

        let thisYear = allCharges
            .filter { cal.component(.year, from: $0.date) == refYear }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let sinceTotal = allCharges.reduce(Decimal.zero) { $0 + $1.amount }
        var sinceLabel = "Since \(SignuFormat.monthYearShort(runs.first!.startDate))"
        if runs.count > 1 { sinceLabel += " · \(runs.count) runs" }

        // MARK: Timeline
        var dated: [(Date, TimelineEvent)] = []

        // Upcoming/expected head event for the latest run.
        if latest.status == .active, let next = latest.nextExpectedDate {
            let rel = SignuFormat.relativeShort(days: dayCount(from: today, to: next))
            dated.append((next, TimelineEvent(
                id: UUID(), title: "Renews",
                dateText: "\(SignuFormat.timelineDate(next, referenceYear: refYear)) · \(rel)",
                amountText: SignuFormat.brl(lastCharge.amount, approximate: approx),
                tone: .normal, marker: .ring
            )))
        } else if latest.status == .overdue, let next = latest.nextExpectedDate {
            dated.append((next, TimelineEvent(
                id: UUID(), title: "Expected charge",
                dateText: "Due \(SignuFormat.timelineDate(next, referenceYear: refYear)) · not seen yet",
                amountText: SignuFormat.brl(lastCharge.amount, approximate: approx),
                tone: .danger, marker: .ring
            )))
        }

        for (runIndex, run) in runs.enumerated() {
            let runCharges = allCharges.filter { $0.runId == run.id }.sorted { $0.date < $1.date }

            for (i, charge) in runCharges.enumerated() {
                let prev = i > 0 ? runCharges[i - 1] : nil
                let dateText = SignuFormat.timelineDate(charge.date, referenceYear: refYear)
                let amount = SignuFormat.brl(charge.amount)

                if run.status == .cancelled, let cd = run.cancelledDate, charge.date > cd {
                    // R5 trailing charge on a cancelled run.
                    dated.append((charge.date, TimelineEvent(
                        id: UUID(), title: "Charged · after cancellation",
                        dateText: dateText, amountText: amount, tone: .warning, marker: .filled
                    )))
                } else if prev == nil {
                    // Oldest charge of the run = boundary event.
                    let boundary = runIndex == 0 ? "First charge · start of run" : "Started · new run"
                    let dt = runIndex == 0 ? dateText : "\(dateText) · charged"
                    dated.append((charge.date, TimelineEvent(
                        id: UUID(), title: boundary, dateText: dt,
                        amountText: amount, tone: .positive, marker: .filled
                    )))
                } else if let prev, charge.amount > prev.amount {
                    dated.append((charge.date, TimelineEvent(
                        id: UUID(), title: "Price raised · was \(SignuFormat.brl(prev.amount))",
                        dateText: dateText, amountText: amount, tone: .warning, marker: .filled
                    )))
                } else if let prev, charge.cardLabel != prev.cardLabel {
                    // Switch-point charge carries the transition annotation.
                    dated.append((charge.date, TimelineEvent(
                        id: UUID(), title: "Charged",
                        dateText: "\(dateText) · card changed to \(charge.cardLabel)",
                        amountText: amount, tone: .info, marker: .filled
                    )))
                } else {
                    // Ordinary charge; inline card only when it differs from current.
                    let dt = charge.cardLabel != currentCard ? "\(dateText) · \(charge.cardLabel)" : dateText
                    dated.append((charge.date, TimelineEvent(
                        id: UUID(), title: "Charged", dateText: dt,
                        amountText: amount, tone: .normal, marker: .filled
                    )))
                }
            }

            // Run-death synthesized events.
            if run.status == .ended, let endDate = run.endDate {
                // Missed expected row only on a standalone ended run (21p);
                // for an older ended run before a gap the gap carries it (21q).
                if run.id == latest.id {
                    dated.append((endDate, TimelineEvent(
                        id: UUID(), title: "Expected charge missed",
                        dateText: SignuFormat.timelineDate(endDate, referenceYear: refYear),
                        amountText: nil, tone: .warning, marker: .ring
                    )))
                }
                let endedDate = cal.date(byAdding: .day, value: 10, to: endDate)!
                dated.append((endedDate, TimelineEvent(
                    id: UUID(), title: "Ended · charges stopped",
                    dateText: "\(SignuFormat.timelineDate(endedDate, referenceYear: refYear)) · paid through \(SignuFormat.monthDay(endDate))",
                    amountText: nil, tone: .muted, marker: .filled
                )))
            }
            if run.status == .cancelled, let cd = run.cancelledDate, let endDate = run.endDate {
                dated.append((cd, TimelineEvent(
                    id: UUID(), title: "Cancelled by you",
                    dateText: "\(SignuFormat.timelineDate(cd, referenceYear: refYear)) · paid through \(SignuFormat.monthDay(endDate))",
                    amountText: nil, tone: .danger, marker: .filled
                )))
            }

            // Gap between this run's death and the next run's start (11a).
            if runIndex < runs.count - 1 {
                let next = runs[runIndex + 1]
                let deadDate = deadDate(of: run, calendar: cal)
                if let deadDate, next.startDate > deadDate {
                    let months = Int((Double(dayCount(from: deadDate, to: next.startDate)) / 30.44).rounded())
                    let gapSort = cal.date(byAdding: .day, value: -1, to: next.startDate)!
                    dated.append((gapSort, TimelineEvent(
                        id: UUID(), title: "Not subscribed",
                        dateText: "\(SignuFormat.monthDay(deadDate)) – \(SignuFormat.monthDay(next.startDate)) · \(months) months",
                        amountText: nil, tone: .muted, marker: .ring, uppercaseTitle: true
                    )))
                }
            }
        }

        var events = dated.sorted { $0.0 > $1.0 }.map(\.1)
        applyConnectors(&events)

        // MARK: Actions + footer
        let showRemindMe = latest.status == .active
        // The stored setting, not a guess. `remind_before_days` nullable IS the
        // switch (v5), so its presence is the whole answer.
        let reminderOn = sub.remindBeforeDays != nil
        let showMarkCancelled = latest.status == .active || latest.status == .overdue
        let footer = detailFooter(latest, lastCharge: lastCharge, calendar: cal)

        return DetailPayload(
            id: sub.id, serviceName: sub.displayName, subtitle: subtitle,
            statusText: statusText, statusTone: statusTone,
            amountText: amountText, unit: unit, dateSlot: dateSlot,
            thisYearText: SignuFormat.brl(thisYear), sinceLabel: sinceLabel,
            sinceTotalText: SignuFormat.brl(sinceTotal), events: events,
            showRemindMe: showRemindMe, reminderOn: reminderOn,
            showMarkCancelled: showMarkCancelled, footer: footer
        )
    }

    // MARK: - Helpers

    private func statusChip(_ status: RunStatus) -> (String, StatusChip.Tone) {
        switch status {
        case .active: ("Active", .positive)
        case .overdue: ("Overdue", .danger)
        case .cancelled: ("Cancelled", .danger)
        case .ended: ("Ended", .neutral)
        case .possible: ("Possible", .neutral)
        }
    }

    private func heroDateSlot(_ run: SubscriptionRun) -> SubscriptionHeroCard.DateSlot {
        switch run.status {
        case .active:
            let next = run.nextExpectedDate ?? today
            let rel = SignuFormat.relativeShort(days: dayCount(from: today, to: next))
            return .renews("\(SignuFormat.monthDay(next)) · \(rel)")
        case .overdue:
            let next = run.nextExpectedDate ?? today
            return .expected("\(SignuFormat.monthDay(next)) · not seen")
        default:
            return .paidThrough(run.endDate.map(SignuFormat.monthDay) ?? SignuFormat.dash)
        }
    }

    private func deadDate(of run: SubscriptionRun, calendar: Calendar) -> Date? {
        switch run.status {
        case .ended: run.endDate.flatMap { calendar.date(byAdding: .day, value: 10, to: $0) }
        case .cancelled: run.cancelledDate
        default: nil
        }
    }

    private func detailFooter(_ run: SubscriptionRun, lastCharge: Charge, calendar: Calendar) -> String? {
        switch run.status {
        case .overdue:
            guard let next = run.nextExpectedDate,
                  let deadline = calendar.date(byAdding: .day, value: 10, to: next) else { return nil }
            return "Expected \(SignuFormat.brl(lastCharge.amount)) on \(SignuFormat.monthDayShort(next)) — nothing yet.\nIf no charge arrives by \(SignuFormat.monthDayShort(deadline)), we'll mark this run ended."
        case .cancelled:
            guard let cd = run.cancelledDate, let end = run.endDate else { return nil }
            return "You cancelled this on \(SignuFormat.monthDayShort(cd)) — paid through \(SignuFormat.monthDayShort(end)).\nIf charges keep coming, two in a row start a new run."
        case .ended:
            guard let end = run.endDate else { return nil }
            return "Charges stopped — paid through \(SignuFormat.monthDayShort(end)).\nIf charges return, two in a row start a new run."
        default:
            return nil
        }
    }

    /// Solid connectors throughout; dashed only around the not-subscribed gap.
    private func applyConnectors(_ events: inout [TimelineEvent]) {
        guard !events.isEmpty else { return }
        events[0].lineAbove = .none
        events[events.count - 1].lineBelow = .none
        for (index, event) in events.enumerated() where event.uppercaseTitle {
            events[index].lineAbove = .dashed
            events[index].lineBelow = .dashed
            if index > 0 { events[index - 1].lineBelow = .dashed }
            if index < events.count - 1 { events[index + 1].lineAbove = .dashed }
        }
    }

    private func cardWithDash(_ label: String) -> String {
        guard let space = label.firstIndex(of: " ") else { return label }
        return label.replacingCharacters(in: space...space, with: " – ")
    }

    private func dayCount(from: Date, to: Date) -> Int {
        Self.calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}

// MARK: - Preview fixtures (not in the Home/Subs dataset)
