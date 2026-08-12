import SwiftUI

/// Loads the subs payload from the provider and renders it.
struct SubsScreen: View {
    let provider: SignuDataProviding
    var actions = SubsActions()
    var initialFilter: SubsFilter = .all
    var initialSortByCost = false
    var scrollAnchor: UnitPoint = .top

    @State private var payload: SubsPayload?

    var body: some View {
        Group {
            if let payload {
                SubsView(
                    payload: payload, actions: actions, filter: initialFilter,
                    sortByCost: initialSortByCost, scrollAnchor: scrollAnchor
                )
            } else {
                Color.clear
            }
        }
        .task {
            payload = try? await provider.subsPayload()
        }
    }
}

struct SubsActions {
    var onSelectSubscription: (UUID) -> Void = { _ in }
    var onReviewSuggestion: (UUID) -> Void = { _ in }   // run id → 9a
    var onSearch: () -> Void = {}
}

enum SubsFilter {
    case all, active, inactive
}

/// Subscriptions tab (7a/8a/9b — mockups 21r/21s/21t).
struct SubsView: View {
    let payload: SubsPayload
    var actions = SubsActions()

    var scrollAnchor: UnitPoint = .top
    @State var filter: SubsFilter
    @State private var sortByCost: Bool

    init(payload: SubsPayload, actions: SubsActions = SubsActions(), filter: SubsFilter = .all,
         sortByCost: Bool = false, scrollAnchor: UnitPoint = .top) {
        self.payload = payload
        self.actions = actions
        self.scrollAnchor = scrollAnchor
        self._filter = State(initialValue: filter)
        self._sortByCost = State(initialValue: sortByCost)
    }

    var body: some View {
        SignuScrollView(anchor: scrollAnchor) {
            VStack(alignment: .leading, spacing: 14) {
                header
                hero
                chips
                    .padding(.bottom, 2)

                switch filter {
                case .all:
                    suggestedSection
                    groupSection(payload.monthly, title: "Monthly", showsSortToggle: true)
                    groupSection(payload.annual, title: "Annual", showsSortToggle: false)
                    inactiveSection
                case .active:
                    groupSection(payload.monthly, title: "Monthly", showsSortToggle: true)
                    groupSection(payload.annual, title: "Annual", showsSortToggle: false)
                case .inactive:
                    inactiveSection
                }
            }
            .padding(.horizontal, SignuMetric.screenPadding)
            .padding(.bottom, SignuMetric.scrollBottomInset)
        }
        .background(SignuColor.paper)
    }

    // MARK: - Header, hero, chips

    private var header: some View {
        HStack {
            Text("Subscriptions")
                .font(.signuScreenTitle)
                .foregroundStyle(SignuColor.textPrimary)
            Spacer()
            ChromeButton(systemName: "magnifyingglass", action: actions.onSearch)
        }
        .padding(.top, 4)
    }

    // Hero is invariant: the chips filter the list only, never these numbers.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 5) {
            OverlineText("All subscriptions")
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(SignuFormat.brl(payload.yearlyTotal, approximate: payload.yearlyApproximate))
                    .font(.signuHeroCompact)
                    .foregroundStyle(SignuColor.textPrimary)
                    .lineLimit(1)
                Text("/yr")
                    .font(.signuSubtitle)
                    .foregroundStyle(SignuColor.textSecondary)
                Spacer(minLength: 8)
                // ÷12 derivation — approximate by construction, always tilde.
                Text("\(SignuFormat.brl(payload.monthlyCompanion, approximate: true)) /mo")
                    .font(.signuSubtitleEmphasis)
                    .foregroundStyle(SignuColor.textSecondary)
                    .fixedSize()
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            FilterChip(label: "All", count: payload.allCount, isSelected: filter == .all) {
                filter = .all
            }
            FilterChip(label: "Active", count: payload.activeCount, isSelected: filter == .active) {
                filter = .active
            }
            FilterChip(label: "Inactive", count: payload.inactiveCount, isSelected: filter == .inactive) {
                filter = .inactive
            }
        }
    }

    // MARK: - Suggested (9b: informs; all actions live on 9a)

    @ViewBuilder
    private var suggestedSection: some View {
        if !payload.suggested.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Suggested · \(payload.suggested.count)", color: SignuColor.green)
                // Shared tinted-alert-surface rule (tint fill + 1px darker-tint
                // stroke) — same treatment as Home's banner/overdue/review pill.
                VStack(spacing: 0) {
                    ForEach(Array(payload.suggested.enumerated()), id: \.element.id) { index, item in
                        suggestedRow(item)
                        if index < payload.suggested.count - 1 {
                            Rectangle()
                                .fill(SignuColor.greenTintStroke.opacity(0.6))
                                .frame(height: 1)
                                .padding(.leading, SignuMetric.rowPaddingH)
                        }
                    }
                }
                .tintedSurface(
                    fill: SignuColor.greenTint,
                    stroke: SignuColor.greenTintStroke,
                    cornerRadius: SignuMetric.cardRadius
                )
            }
            .padding(.top, 2)
        }
    }

    private func suggestedRow(_ item: SubsPayload.SuggestedItem) -> some View {
        Button {
            actions.onReviewSuggestion(item.id)
        } label: {
            HStack(spacing: 12) {
                ServiceAvatar(name: item.serviceName)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.serviceName)
                        .font(.signuRowTitle)
                        .foregroundStyle(SignuColor.textPrimary)
                    // 13pt + slight scale: largest that keeps the locked
                    // evidence copy on one line in Inter (21t face is narrower).
                    Text(item.evidence)
                        .font(SignuFont.font(13, .semibold, tabular: true))
                        .foregroundStyle(SignuColor.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SignuColor.green)
            }
            .padding(.vertical, SignuMetric.rowPaddingV)
            .padding(.horizontal, SignuMetric.rowPaddingH)
            // Same rule as SignuRow, which this row does not use because its
            // evidence line carries its own type treatment: a plain button
            // hit-tests only what it draws.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Groups (native-unit subtotals; per-group sorting)

    @ViewBuilder
    private func groupSection(_ group: SubsPayload.Group, title: String, showsSortToggle: Bool) -> some View {
        if !group.rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    OverlineText("\(title) · \(SignuFormat.brl(group.subtotal, approximate: group.approximate))")
                    Spacer()
                    if showsSortToggle {
                        // Global control for both groups; sits on the
                        // MONTHLY header row (accepted placement).
                        SortToggle(options: ["By date", "By cost"], selection: Binding(
                            get: { sortByCost ? 1 : 0 },
                            set: { sortByCost = $0 == 1 }
                        ))
                    }
                }
                SignuListCard(data: sortedRows(group)) { row in
                    groupRow(row)
                }
            }
            .padding(.top, 2)
        }
    }

    // By date = next-charge order (overdue floats up for free);
    // By cost = descending amount, within the group.
    private func sortedRows(_ group: SubsPayload.Group) -> [SubsPayload.Row] {
        sortByCost ? group.rows.sorted { $0.amount > $1.amount } : group.rows
    }

    private func groupRow(_ row: SubsPayload.Row) -> some View {
        Button {
            actions.onSelectSubscription(row.id)
        } label: {
            VStack(spacing: 8) {
                SignuRow(
                    title: row.serviceName,
                    subtitle: row.overdueDays.map { Text("Overdue · \($0) days").foregroundStyle(SignuColor.red) }
                        ?? Text(row.subtitle),
                    trailingTitle: Text(SignuFormat.brl(row.amount, approximate: row.approximate)),
                    trailingSubtitle: sortByCost
                        ? Text("\(Int((row.share * 100).rounded()))% of total")
                        : Text(SignuFormat.monthDay(row.nextDate))
                            .foregroundStyle(row.overdueDays != nil ? SignuColor.red : SignuColor.textSecondary)
                ) {
                    ServiceAvatar(name: row.serviceName)
                }
                if sortByCost {
                    shareBar(row.share)
                        .padding(.horizontal, SignuMetric.rowPaddingH)
                        .padding(.bottom, 10)
                        .padding(.top, -6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func shareBar(_ share: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SignuColor.sunken.opacity(0.8))
                Capsule()
                    .fill(SignuColor.ink.opacity(0.8))
                    .frame(width: max(4, proxy.size.width * share))
            }
        }
        .frame(height: 4)
    }

    // MARK: - Inactive (8a: flat list, no groups, no sort)

    @ViewBuilder
    private var inactiveSection: some View {
        if !payload.inactive.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Inactive · \(payload.inactiveCount)")
                SignuListCard(data: payload.inactive) { item in
                    inactiveRow(item)
                }
                // True for both statuses; honest about the one-cycle blind spot.
                Text("If charges come back, two in a row start a new run.")
                    .font(.signuSubtitle)
                    .foregroundStyle(SignuColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding(.top, 2)
        }
    }

    private func inactiveRow(_ item: SubsPayload.InactiveItem) -> some View {
        Button {
            actions.onSelectSubscription(item.id)
        } label: {
            // Same vertical rhythm as the active rows (SignuRow) — avatar,
            // leading title/subtitle, trailing two-line rail — so the row
            // height is driven by the 44pt avatar and stays interchangeable
            // with the active list rows above it.
            HStack(spacing: 12) {
                ServiceAvatar(name: item.serviceName)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.serviceName)
                        .font(.signuRowTitle)
                        .foregroundStyle(SignuColor.textPrimary)
                        .lineLimit(1)
                    // One compact line: "Was R$ X /mo". "Was" framing =
                    // historical fact — never a tilde here. Scale down a hair
                    // before truncating (guards wider amounts, e.g.
                    // "Was R$ 199,90 /yr", from clipping).
                    Text(item.statusText)
                        .font(SignuFont.font(14))
                        .foregroundStyle(SignuColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .truncationMode(.tail)
                }
                // Left column takes the slack so the fixed-width right rail
                // never squeezes the title/subtitle.
                .frame(maxWidth: .infinity, alignment: .leading)
                // Right rail mirrors the left: chip-over-date opposite
                // title-over-subtitle. Compact chip keeps the rail ≤ 44pt.
                VStack(alignment: .trailing, spacing: 3) {
                    StatusChip(
                        text: item.cancelled ? "Cancelled" : "Ended",
                        tone: item.cancelled ? .danger : .neutral,
                        compact: true
                    )
                    // Billing state, not access state — paid-through carries
                    // the access story. 14pt (not 15) keeps this longer string
                    // from widening the rail into the title.
                    Text(item.paidThroughText)
                        .font(SignuFont.font(14))
                        .foregroundStyle(SignuColor.textSecondary)
                        .fixedSize()
                }
            }
            .padding(.vertical, SignuMetric.rowPaddingV)
            .padding(.horizontal, SignuMetric.rowPaddingH)
            // As SignuRow. Inactive rows are hand-built because the right rail is
            // chip-over-date rather than value-over-date.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// Tab screens are reviewed inside AppShellView (tab bar overlaid) so clearance
// and the Safari-style hide/show behavior are visible (tab bar contract v13).
#Preview("Subs · All (21t)") {
    AppShellView(provider: MockDataProvider(), initialTab: .subs)
}

#Preview("Subs · Inactive (21s)") {
    AppShellView(provider: MockDataProvider(), initialTab: .subs, initialSubsFilter: .inactive)
}

#Preview("Subs · Active") {
    AppShellView(provider: MockDataProvider(), initialTab: .subs, initialSubsFilter: .active)
}

// Bottom-of-scroll spacing must be reviewed in context: shell + tab bar,
// pre-scrolled to the very end (mirrors the Home bottom-inset preview).
#Preview("Subs · in shell, scrolled to bottom") {
    AppShellView(provider: MockDataProvider(), initialTab: .subs, subsScrollAnchor: .bottom)
}
