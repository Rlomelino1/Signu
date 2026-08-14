import Foundation

/// Calendar assembly, shared by both providers like every other payload — so the
/// screen has one implementation and cannot drift between preview and production.
extension SignuPayloadSource {

    /// Six rows of seven. Six because that is the most weeks a month can span, and
    /// fixed because a grid that resizes per month moves everything under it.
    static var gridCellCount: Int { 42 }

    func makeCalendarPayload(monthContaining date: Date) -> CalendarPayload {
        let calendar = Self.calendar
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)!.count

        // `weekday` is 1-based from the calendar's first weekday (Sunday here),
        // and the grid needs an offset, so this is a subtraction rather than the
        // value itself.
        let leadingBlanks = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7

        // A CONSTANT SIX ROWS (v46). A grid sized to each month exactly changes
        // height as the user pages — 28 days from a Sunday needs four rows, 31 from
        // a Saturday needs six — and the layout below it moves under the thumb.
        // The spare cells carry the adjacent months' real days rather than blanks,
        // so the week rows stay readable as weeks.
        let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)!
        let previousDayCount = calendar.range(of: .day, in: .month, for: previousMonthStart)!.count
        let leadingDays = leadingBlanks > 0
            ? Array((previousDayCount - leadingBlanks + 1)...previousDayCount)
            : []
        // Six weeks is the most any month can span, so this is never negative:
        // the widest case is 31 days starting on the last weekday, 6 + 31 = 37.
        let trailingCount = Self.gridCellCount - leadingBlanks - dayCount
        let trailingDays = trailingCount > 0 ? Array(1...trailingCount) : []

        // Same visibility rule as every other payload: a dismissed subscription's
        // runs are not part of the picture, and a `possible` run is a suggestion
        // rather than a renewal.
        let visible = runList.filter { run in
            subscriptionFor(run.subscriptionId).map { !$0.ignored } ?? false
        }

        var entries: [CalendarPayload.Entry] = []

        // Backwards: every charge that landed in this month, for EVERY run state.
        // A charge is a fact — a run that was cancelled in June still cost money
        // in May, and scoping this to active runs the way the forward pass does
        // would report a cheaper past than the ledger holds.
        for run in visible {
            guard let sub = subscriptionFor(run.subscriptionId) else { continue }
            for charge in chargeList
            where charge.runId == run.id
                && calendar.isDate(charge.date, equalTo: monthStart, toGranularity: .month) {
                entries.append(
                    CalendarPayload.Entry(
                        id: charge.id,
                        subscriptionId: sub.id,
                        serviceName: sub.displayName,
                        day: calendar.component(.day, from: charge.date),
                        date: charge.date,
                        amount: charge.amount,
                        // Never approximate, regardless of how the run was
                        // detected: the tilde marks a predicted amount, and this
                        // one is what the bank actually charged. R3's uncertainty
                        // is about the NEXT amount, not a past one.
                        approximate: false,
                        kind: .paid
                    )
                )
            }
        }

        // Forwards: the one renewal per run the engine stated, and no further.
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
                    kind: run.status == .overdue ? .overdue : .expected
                )
            )
        }

        // Paid before expected within a day, then by name — so a day holding both
        // reads in the order the events happen rather than alphabetically across
        // two different kinds of fact.
        let byDay = Dictionary(grouping: entries, by: \.day)
            .mapValues { dayEntries in
                dayEntries.sorted {
                    $0.kind.sortRank == $1.kind.sortRank
                        ? $0.serviceName < $1.serviceName
                        : $0.kind.sortRank < $1.kind.sortRank
                }
            }

        return CalendarPayload(
            monthStart: monthStart,
            monthLabel: SignuFormat.monthYearFull(monthStart),
            leadingDays: leadingDays,
            trailingDays: trailingDays,
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
