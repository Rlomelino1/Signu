import Foundation

extension SignuPayloadSource {

    static var gridCellCount: Int { 42 }

    func makeCalendarPayload(monthContaining date: Date) -> CalendarPayload {
        let calendar = Self.calendar
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)!.count

        let leadingBlanks = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7

        let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)!
        let previousDayCount = calendar.range(of: .day, in: .month, for: previousMonthStart)!.count
        let leadingDays = leadingBlanks > 0
            ? Array((previousDayCount - leadingBlanks + 1)...previousDayCount)
            : []
        let trailingCount = Self.gridCellCount - leadingBlanks - dayCount
        let trailingDays = trailingCount > 0 ? Array(1...trailingCount) : []

        let visible = runList.filter { run in
            subscriptionFor(run.subscriptionId).map { !$0.ignored } ?? false
        }

        var entries: [CalendarPayload.Entry] = []

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
                        approximate: false,
                        kind: .paid
                    )
                )
            }
        }

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


    private func subscriptionFor(_ id: UUID) -> Subscription? {
        subscriptionList.first { $0.id == id }
    }

    private func latestChargeFor(_ runId: UUID) -> Charge? {
        chargeList.filter { $0.runId == runId }.max { $0.date < $1.date }
    }
}
