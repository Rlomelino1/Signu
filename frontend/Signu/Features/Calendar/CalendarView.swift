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
    /// Months from the provider's today to open on. Zero in the app; the debug
    /// harness passes an offset so a past month can be screenshotted directly
    /// rather than by tapping the pager a known number of times.
    var startingMonthOffset: Int = 0

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
            let start = monthStart
                ?? SignuCalendar.saoPaulo.date(
                    byAdding: .month, value: startingMonthOffset, to: provider.today
                )
                ?? provider.today
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

    /// One grid cell, identified by which month its day belongs to as well as the
    /// number — a bare day number is not unique across a six-row grid.
    private struct GridCell: Identifiable {
        enum Position: String { case before, inMonth, after }
        let position: Position
        let day: Int
        var id: String { "\(position.rawValue)-\(day)" }
        var isInMonth: Bool { position == .inMonth }
    }

    private var cells: [GridCell] {
        payload.leadingDays.map { GridCell(position: .before, day: $0) }
            + (1...payload.dayCount).map { GridCell(position: .inMonth, day: $0) }
            + payload.trailingDays.map { GridCell(position: .after, day: $0) }
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
                Text("Nothing charged or expected in \(payload.monthLabel).")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
            } else {
                // "this month" rather than "expected": the figure now covers what
                // was paid as well as what is still coming, and calling that
                // "expected" would misdescribe the larger half of a past month.
                Text("\(SignuFormat.brl(payload.monthTotal, approximate: payload.monthApproximate)) this month")
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

            // Always six rows: the adjacent months fill what this one doesn't
            // reach, so paging does not resize the grid or the screen under it.
            //
            // ONE ForEach over pre-identified cells, not three over Int ranges.
            // Three siblings share one identity space here, and the trailing days
            // (1…11) collide with the month's own 1…11 — SwiftUI silently dropped
            // them and the sixth row rendered as empty space. The identity carries
            // which month a day belongs to for exactly that reason.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells) { cell in
                    if cell.isInMonth {
                        dayCell(cell.day)
                    } else {
                        adjacentDayCell(cell.day)
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: SignuMetric.cardRadius, style: .continuous))
    }

    /// A day belonging to the month before or after this one: shown so the grid
    /// reads as continuous weeks, muted and inert so it cannot be mistaken for
    /// this month's data. Tapping it does nothing rather than paging, because a
    /// tap that both changes month and selects a day is two actions from one
    /// gesture — and `onStep` already exists for the first.
    private func adjacentDayCell(_ day: Int) -> some View {
        Text("\(day)")
            .font(SignuFont.font(15, .regular, tabular: true))
            .foregroundStyle(SignuColor.textTertiary.opacity(0.55))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .accessibilityHidden(true)
    }

    private func dayCell(_ day: Int) -> some View {
        let dayEntries = payload.entriesByDay[day] ?? []
        let isSelected = selectedDay == day
        let isToday = payload.todayDay == day

        return Button {
            // Tapping the selected day clears the filter rather than doing
            // nothing, so the whole month is always one tap away.
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(SignuFont.font(15, isToday ? .bold : .regular, tabular: true))
                    .foregroundStyle(isSelected ? SignuColor.onInk : SignuColor.textPrimary)
                // Three states, in priority order: a missed renewal is the thing
                // to notice, then something still expected, then a day that is
                // only history. Muting the history keeps the green dot meaning
                // "money is still going to move" rather than "something happened".
                Circle()
                    .fill(dotColor(dayEntries))
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

    private func subtitle(for entry: CalendarPayload.Entry) -> Text {
        switch entry.kind {
        case .paid:
            Text("Paid · \(SignuFormat.weekdayMonthDay(entry.date))")
        case .expected:
            Text("Expected · \(SignuFormat.weekdayMonthDay(entry.date))")
        case .overdue:
            Text("Overdue · expected \(SignuFormat.monthDay(entry.date))")
                .foregroundStyle(SignuColor.red)
        }
    }

    private func dotColor(_ entries: [CalendarPayload.Entry]) -> Color {
        if entries.contains(where: { $0.kind == .overdue }) { return SignuColor.red }
        if entries.contains(where: { $0.kind == .expected }) { return SignuColor.green }
        return entries.isEmpty ? .clear : SignuColor.textTertiary
    }

    private func accessibilityLabel(day: Int, entries: [CalendarPayload.Entry]) -> String {
        guard !entries.isEmpty else { return "\(day)" }
        // Counted by kind rather than lumped as "renewals": VoiceOver should not
        // call a charge that already landed a renewal that is coming.
        let paid = entries.filter { $0.kind == .paid }.count
        let ahead = entries.count - paid
        let parts = [
            paid > 0 ? "\(paid) charged" : nil,
            ahead > 0 ? "\(ahead) expected" : nil,
        ].compactMap { $0 }
        return "\(day), \(parts.joined(separator: ", "))"
    }

    @ViewBuilder
    private var list: some View {
        if entries.isEmpty {
            Text(selectedDay == nil
                 ? "No charges landed this month, and nothing is expected. Ahead, Signu shows only the next expected charge of each subscription — it doesn't guess further."
                 : "Nothing charged or expected on that day.")
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
                            // The row says which kind of fact it is. Without it a
                            // past charge and a forecast are one list of dates and
                            // amounts, and the reader cannot tell which already
                            // left their account.
                            subtitle: subtitle(for: entry),
                            trailingTitle: Text(SignuFormat.brl(entry.amount, approximate: entry.approximate))
                        ) {
                            DateBadge(date: entry.date, overdue: entry.overdue)
                        }
                    }
                    .buttonStyle(.plain)
                }
                // States the FORWARD limit on screen rather than leaving a thin
                // month to read as lost data. Past months are complete, so the
                // sentence is scoped to what lies ahead.
                Text("Past charges are complete. Ahead, only the next expected charge of each subscription is shown.")
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
