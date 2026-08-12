import SwiftUI

/// The renewal calendar, reached from Home's "Coming up · Calendar".
///
/// No mockup — designed to the system, like the R4 interval sheet: paper ground,
/// ink hero type, the same row and chip components everywhere else uses. It
/// exists because the Calendar control has been on the Home screen since the
/// contract was locked and has never had a destination.
///
/// It renders exactly what the engine predicted and nothing more. See
/// `CalendarPayload` for why a month can legitimately be empty.
struct CalendarScreen: View {
    let provider: SignuDataProviding
    var onSelectSubscription: (UUID) -> Void = { _ in }
    var onBack: () -> Void = {}

    @State private var monthStart: Date?
    @State private var payload: CalendarPayload?
    @State private var selectedDay: Int?

    var body: some View {
        Group {
            if let payload {
                CalendarView(
                    payload: payload,
                    selectedDay: $selectedDay,
                    onBack: onBack,
                    onSelectSubscription: onSelectSubscription,
                    onStep: { months in step(months, from: payload) }
                )
            } else {
                Color.clear
            }
        }
        .task {
            guard payload == nil else { return }
            let start = monthStart ?? provider.today
            monthStart = start
            payload = try? await provider.calendarPayload(monthContaining: start)
            // Opens on the whole month, with today merely marked. Selecting today
            // by default seemed obvious and was wrong: most days have nothing on
            // them, so the calendar would open on "Nothing renews on that day"
            // while the month behind it was full. The grid shows where things
            // are; the list should show what they are.
        }
    }

    private func step(_ months: Int, from current: CalendarPayload) {
        guard let next = SignuCalendar.saoPaulo.date(byAdding: .month, value: months, to: current.monthStart)
        else { return }
        monthStart = next
        Task {
            payload = try? await provider.calendarPayload(monthContaining: next)
            // A day number means nothing in the month you just arrived at.
            selectedDay = nil
        }
    }
}

struct CalendarView: View {
    let payload: CalendarPayload
    @Binding var selectedDay: Int?
    var onBack: () -> Void = {}
    var onSelectSubscription: (UUID) -> Void = { _ in }
    var onStep: (Int) -> Void = { _ in }

    /// Sunday-first initials. Hard-coded rather than taken from the locale
    /// because the grid's leading offset is computed against the same calendar,
    /// and two sources for one convention is how a month renders a day out.
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    private var entries: [CalendarPayload.Entry] {
        if let selectedDay { return payload.entriesByDay[selectedDay] ?? [] }
        return payload.allEntries
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    ChromeButton(systemName: "chevron.left", action: onBack)
                    Spacer()
                }
                .padding(.top, 4)

                header
                grid
                list
            }
            .padding(.horizontal, SignuMetric.screenPadding)
            .padding(.bottom, SignuMetric.scrollBottomInset)
        }
        .background(SignuColor.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Renewals")
                .font(.signuScreenTitle)
                .foregroundStyle(SignuColor.textPrimary)

            HStack(spacing: 12) {
                stepButton(systemName: "chevron.left", months: -1)
                Text(payload.monthLabel)
                    .font(.signuSection)
                    .foregroundStyle(SignuColor.textPrimary)
                    .frame(maxWidth: .infinity)
                stepButton(systemName: "chevron.right", months: 1)
            }

            if payload.isEmpty {
                Text("Nothing expected in \(payload.monthLabel).")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
            } else {
                Text("\(SignuFormat.brl(payload.monthTotal, approximate: payload.monthApproximate)) expected")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
            }
        }
    }

    private func stepButton(systemName: String, months: Int) -> some View {
        Button { onStep(months) } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SignuColor.textPrimary)
                .frame(width: 40, height: 36)
                .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(months < 0 ? "Previous month" : "Next month")
    }

    private var grid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(SignuFont.font(12, .semibold, tabular: true))
                        .foregroundStyle(SignuColor.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<payload.leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 44)
                }
                ForEach(1...payload.dayCount, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: SignuMetric.cardRadius, style: .continuous))
    }

    private func dayCell(_ day: Int) -> some View {
        let dayEntries = payload.entriesByDay[day] ?? []
        let isSelected = selectedDay == day
        let isToday = payload.todayDay == day
        let hasOverdue = dayEntries.contains { $0.overdue }

        return Button {
            // Tapping the selected day clears the filter rather than doing
            // nothing, so the whole month is always one tap away.
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(SignuFont.font(15, isToday ? .bold : .regular, tabular: true))
                    .foregroundStyle(isSelected ? SignuColor.onInk : SignuColor.textPrimary)
                Circle()
                    .fill(dayEntries.isEmpty
                          ? Color.clear
                          : (hasOverdue ? SignuColor.red : SignuColor.green))
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SignuColor.ink)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SignuColor.sunken)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(day: day, entries: dayEntries))
    }

    private func accessibilityLabel(day: Int, entries: [CalendarPayload.Entry]) -> String {
        guard !entries.isEmpty else { return "\(day)" }
        return "\(day), \(entries.count) renewal\(entries.count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private var list: some View {
        if entries.isEmpty {
            Text(selectedDay == nil
                 ? "Signu only shows the next expected charge of each subscription — it doesn't guess further ahead."
                 : "Nothing renews on that day.")
                .font(.signuSubtitle)
                .foregroundStyle(SignuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(selectedDay == nil ? "This month" : SignuFormat.monthDay(entries[0].date))
                SignuListCard(data: entries) { entry in
                    Button { onSelectSubscription(entry.subscriptionId) } label: {
                        SignuRow(
                            title: entry.serviceName,
                            subtitle: entry.overdue
                                ? Text("Overdue · expected \(SignuFormat.monthDay(entry.date))")
                                    .foregroundStyle(SignuColor.red)
                                : Text(SignuFormat.weekdayMonthDay(entry.date)),
                            trailingTitle: Text(SignuFormat.brl(entry.amount, approximate: entry.approximate))
                        ) {
                            DateBadge(date: entry.date, overdue: entry.overdue)
                        }
                    }
                    .buttonStyle(.plain)
                }
                // States the limit on screen rather than leaving a thin month to
                // read as lost data.
                Text("Only the next expected charge of each subscription is shown.")
                    .font(SignuFont.font(13))
                    .foregroundStyle(SignuColor.textTertiary)
                    .padding(.top, 2)
            }
        }
    }
}

#Preview("Renewal calendar") {
    CalendarScreen(provider: MockDataProvider())
}
