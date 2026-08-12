import Foundation

/// Calendar assembly, shared by both providers like every other payload — so the
/// screen has one implementation and cannot drift between preview and production.
extension SignuPayloadSource {

    func makeCalendarPayload(monthContaining date: Date) -> CalendarPayload {
        let calendar = Self.calendar
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)!.count

        // `weekday` is 1-based from the calendar's first weekday (Sunday here),
        // and the grid needs an offset, so this is a subtraction rather than the
        // value itself.
        let leadingBlanks = calendar.component(.weekday, from: monthStart) - calendar.firstWeekday

        // Same visibility rule as every other payload: a dismissed subscription's
        // runs are not part of the picture, and a `possible` run is a suggestion
        // rather than a renewal.
        let visible = runList.filter { run in
            subscriptionFor(run.subscriptionId).map { !$0.ignored } ?? false
        }

        var entries: [CalendarPayload.Entry] = []
        for run in visible where run.status == .active || run.status == .overdue {
            guard let next = run.nextExpectedDate,
                  calendar.isDate(next, equalTo: monthStart, toGranularity: .month),
                  let sub = subscriptionFor(run.subscriptionId),
                  let last = latestChargeFor(run.id) else { continue }
            entries.append(
                CalendarPayload.Entry(
                    id: run.id,
                    subscriptionId: sub.id,
                    serviceName: sub.displayName,
                    day: calendar.component(.day, from: next),
                    date: next,
                    amount: last.amount,
                    approximate: run.detectedBy.isApproximate,
                    overdue: run.status == .overdue
                )
            )
        }

        let byDay = Dictionary(grouping: entries, by: \.day)
            .mapValues { $0.sorted { $0.serviceName < $1.serviceName } }

        return CalendarPayload(
            monthStart: monthStart,
            monthLabel: SignuFormat.monthYearFull(monthStart),
            leadingBlanks: (leadingBlanks + 7) % 7,
            dayCount: dayCount,
            todayDay: calendar.isDate(today, equalTo: monthStart, toGranularity: .month)
                ? calendar.component(.day, from: today)
                : nil,
            entriesByDay: byDay,
            monthTotal: entries.reduce(Decimal.zero) { $0 + $1.amount },
            monthApproximate: entries.contains { $0.approximate }
        )
    }

    // Local copies rather than shared ones, matching how PayloadSource+Settings
    // does it: each payload file owns the small lookups it needs, so none of them
    // can quietly change what another reads.

    private func subscriptionFor(_ id: UUID) -> Subscription? {
        subscriptionList.first { $0.id == id }
    }

    private func latestChargeFor(_ runId: UUID) -> Charge? {
        chargeList.filter { $0.runId == runId }.max { $0.date < $1.date }
    }
}
