import SwiftUI

/// Loads a detail payload (real subscription or a preview fixture) and renders it.
struct DetailScreen: View {
    var payload: DetailPayload?
    var loader: (() async -> DetailPayload?)?
    var actions = DetailActions()
    var scrollAnchor: UnitPoint = .top

    @State private var loaded: DetailPayload?

    var body: some View {
        Group {
            if let payload = payload ?? loaded {
                DetailView(payload: payload, actions: editing(actions), scrollAnchor: scrollAnchor)
            } else {
                Color.clear
            }
        }
        .task {
            if payload == nil { loaded = await loader?() }
        }
    }

    /// Re-reads after an edit that this screen displays.
    ///
    /// Renaming changes the hero the user is looking at, so leaving the old name
    /// on screen would be the two-representations-of-one-row problem the write
    /// boundary exists to avoid (v29) — just locally instead of across screens.
    /// The wrapping happens here rather than at the shell's call site because the
    /// payload lives here and nothing else can reload it.
    private func editing(_ actions: DetailActions) -> DetailActions {
        var wrapped = actions
        wrapped.onRename = { name in
            await actions.onRename(name)
            loaded = await loader?()
        }
        wrapped.onChangeCategory = { category in
            await actions.onChangeCategory(category)
            loaded = await loader?()
        }
        return wrapped
    }
}

struct DetailActions {
    var onBack: () -> Void = {}
    /// The overflow menu's two actions. `onMore` used to sit here as a single
    /// closure nobody supplied — the ellipsis was a button that opened nothing —
    /// and the menu itself is now local to the view, because presenting a menu is
    /// not a decision the shell has any part in. nil clears the value.
    /// `async` on purpose: the screen re-reads itself when one of these returns,
    /// and a fire-and-forget closure would race the write it is meant to show. The
    /// hero renders the name being changed, so "eventually correct" is visibly
    /// wrong here in a way it is not for the reminder toggle.
    var onRename: (String?) async -> Void = { _ in }
    var onChangeCategory: (String?) async -> Void = { _ in }
    var onToggleReminder: (Bool) -> Void = { _ in }
    var onMarkCancelled: () -> Void = {}
}

/// Subscription detail (mockups 21k–21q): ink hero + self-narrating timeline.
struct DetailView: View {
    let payload: DetailPayload
    var actions = DetailActions()
    @State private var editing: Editing?

    /// Seeded from the payload, so the label matches what is stored. `@State`
    /// rather than reading the payload directly because the tap must show
    /// immediately — the write is fire-and-forget and the row is only re-read on
    /// the next visit.
    @State private var reminderOn: Bool
    var scrollAnchor: UnitPoint = .top

    init(payload: DetailPayload, actions: DetailActions = DetailActions(), scrollAnchor: UnitPoint = .top) {
        self.payload = payload
        self.actions = actions
        self.scrollAnchor = scrollAnchor
        self._reminderOn = State(initialValue: payload.reminderOn)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    topChrome
                    hero
                    // History sits tight under the hero (21q).
                    VStack(alignment: .leading, spacing: 8) {
                        Text("History")
                            .font(.signuSection)
                            .foregroundStyle(SignuColor.textPrimary)
                        timeline
                    }
                }
                .padding(.horizontal, SignuMetric.screenPadding)
                .padding(.bottom, 150)
            }
            .defaultScrollAnchor(scrollAnchor)
            bottomBar
        }
        .background(SignuColor.paper)
        .sheet(item: $editing) { which in
            switch which {
            case .rename:
                RenameSheet(
                    // The ENGINE's name: the placeholder and the reset action are
                    // both about what shows through when the nickname is gone.
                    serviceName: payload.engineName,
                    nickname: payload.nickname,
                    onSave: { name in
                        editing = nil
                        Task { await actions.onRename(name) }
                    }
                )
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
            case .category:
                CategorySheet(
                    serviceName: payload.serviceName,
                    current: payload.category,
                    known: payload.knownCategories,
                    onSave: { category in
                        editing = nil
                        Task { await actions.onChangeCategory(category) }
                    }
                )
                .presentationDetents([.height(520)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var topChrome: some View {
        HStack {
            ChromeButton(systemName: "chevron.left", action: actions.onBack)
            Spacer()
            // A native menu rather than a sheet of choices: two actions, both
            // one-tap destinations of their own.
            Menu {
                Button("Rename…") { editing = .rename }
                Button(payload.category == nil ? "Add category…" : "Change category…") {
                    editing = .category
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SignuColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(SignuColor.surface, in: Circle())
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    .contentShape(Circle())
            }
            .accessibilityLabel("More")
        }
        .padding(.top, 4)
    }

    /// Which overflow sheet is up. One optional rather than two booleans — the
    /// same lesson 14a's empty sheet taught: one presentation, one piece of state.
    enum Editing: String, Identifiable {
        case rename, category
        var id: String { rawValue }
    }

    private var hero: some View {
        SubscriptionHeroCard(
            serviceName: payload.serviceName,
            subtitle: payload.subtitle,
            statusText: payload.statusText,
            statusTone: payload.statusTone,
            amount: payload.amountText,
            unit: payload.unit,
            dateSlot: payload.dateSlot,
            stats: [
                ("This year", payload.thisYearText),
                (payload.sinceLabel, payload.sinceTotalText),
            ]
        )
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(payload.events) { event in
                TimelineRow(event: event)
            }
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if payload.footer != nil || payload.showRemindMe || payload.showMarkCancelled {
            VStack(spacing: 14) {
                if let footer = payload.footer {
                    Text(footer)
                        .font(.signuSubtitle)
                        .foregroundStyle(SignuColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if payload.showRemindMe || payload.showMarkCancelled {
                    HStack(spacing: 12) {
                        if payload.showRemindMe { remindButton }
                        if payload.showMarkCancelled {
                            Button(action: actions.onMarkCancelled) {
                                Text("Mark cancelled").lineLimit(1)
                            }
                            .buttonStyle(.signuDestructiveOutline)
                        }
                    }
                }
            }
            .padding(.horizontal, SignuMetric.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(alignment: .top) {
                SignuColor.paper
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        Rectangle().fill(SignuColor.hairline).frame(height: 1)
                    }
            }
        }
    }

    // Reminder toggle → subscription.remind_before_days (on = 2). No mockup
    // for the on-state; rendered as a green confirmed pill.
    private var remindButton: some View {
        Button {
            reminderOn.toggle()
            actions.onToggleReminder(reminderOn)
        } label: {
            Label(reminderOn ? "Reminder on" : "Remind me",
                  systemImage: reminderOn ? "bell.fill" : "bell")
                .lineLimit(1)
        }
        .buttonStyle(SignuButtonStyle(kind: reminderOn ? .success : .primary))
    }
}

/// One timeline row: leading rail (connector + marker) and the event content.
private struct TimelineRow: View {
    let event: TimelineEvent

    private let markerCenter: CGFloat = 20
    private let markerSize: CGFloat = 11

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rail
            VStack(alignment: .leading, spacing: 2) {
                title
                Text(event.dateText)
                    .font(SignuFont.font(14))
                    .foregroundStyle(SignuColor.textSecondary)
            }
            .padding(.vertical, 10)
            .layoutPriority(1)          // label wins space over the amount
            Spacer(minLength: 6)
            if let amount = event.amountText {
                Text(amount)
                    .font(.signuRowTitle)
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var title: some View {
        if event.uppercaseTitle {
            OverlineText(event.title, color: SignuColor.textSecondary)
        } else {
            Text(event.title)
                .font(.signuRowTitle)
                .foregroundStyle(event.tone == .normal ? SignuColor.textPrimary : tone)
                .lineLimit(1)
                .minimumScaleFactor(0.8)   // one line — all timeline labels (21o)
        }
    }

    private var rail: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                RailLine(style: event.lineAbove).frame(height: markerCenter)
                RailLine(style: event.lineBelow).frame(maxHeight: .infinity)
            }
            marker
                .frame(width: markerSize, height: markerSize)
                .offset(y: markerCenter - markerSize / 2)
        }
        .frame(width: 16)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var marker: some View {
        switch event.marker {
        case .filled:
            Circle().fill(tone)
        case .ring:
            Circle().fill(SignuColor.paper)
                .overlay(Circle().strokeBorder(tone, lineWidth: 2.5))
        }
    }

    private var tone: Color {
        switch event.tone {
        case .normal: SignuColor.textPrimary
        case .positive: SignuColor.green
        case .warning: SignuColor.gold
        case .danger: SignuColor.red
        case .info: SignuColor.blue
        case .muted: SignuColor.textSecondary
        }
    }
}

/// Vertical connector segment — solid, dashed, or nothing.
private struct RailLine: View {
    let style: TimelineEvent.Line

    var body: some View {
        switch style {
        case .none:
            Color.clear.frame(width: 16)
        case .solid:
            VLineShape().stroke(SignuColor.hairline, style: StrokeStyle(lineWidth: 2))
                .frame(width: 16)
        case .dashed:
            VLineShape().stroke(SignuColor.textTertiary, style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                .frame(width: 16)
        }
    }
}

private struct VLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - Previews

/// Detail payload for the real subscription with the given service name.
///
/// `@MainActor` because the providers are: this builds one, and a nonisolated
/// async helper could otherwise touch it from any executor.
@MainActor
private func detailByName(_ name: String) async -> DetailPayload? {
    let provider = MockDataProvider()
    guard let sub = (try? await provider.subscriptions())?.first(where: { $0.serviceName == name })
    else { return nil }
    return try? await provider.detailPayload(subscriptionId: sub.id)
}

#Preview("Detail · active (21k/21l)") {
    DetailScreen(loader: { await detailByName("Netflix") })
}

#Preview("Detail · overdue (21m)") {
    DetailScreen(loader: { await detailByName("Globoplay") })
}

#Preview("Detail · card change (21n)") {
    DetailScreen(loader: { await detailByName("Spotify") })
}

#Preview("Detail · cancelled + trailing (21o)") {
    let provider = MockDataProvider()
    let (sub, runs, charges) = MockDataProvider.demoCancelledTrailing()
    return DetailScreen(payload: provider.detailPayload(subscription: sub, runs: runs, charges: charges))
}

#Preview("Detail · ended (21p)") {
    DetailScreen(loader: { await detailByName("Amazon Prime") })
}

#Preview("Detail · multi-run (21q)") {
    let provider = MockDataProvider()
    let (sub, runs, charges) = MockDataProvider.demoMax()
    return DetailScreen(payload: provider.detailPayload(subscription: sub, runs: runs, charges: charges))
}
