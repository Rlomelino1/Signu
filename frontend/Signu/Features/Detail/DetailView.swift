import SwiftUI

struct DetailScreen: View {
    var payload: DetailPayload?
    var loader: (() async throws -> DetailPayload?)?
    var actions = DetailActions()
    var scrollAnchor: UnitPoint = .top

    @State private var loaded: DetailPayload?
    @State private var failure: String?

    var body: some View {
        Group {
            if let payload = payload ?? loaded {
                DetailView(payload: payload, actions: editing(actions), scrollAnchor: scrollAnchor)
            } else if let failure {
                LoadFailureView(message: failure) { await load() }
            } else {
                Color.clear
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard payload == nil, let loader else { return }
        do {
            loaded = try await loader()
            failure = nil
        } catch {
            switch LoadFailureRoute.of(hasPayload: loaded != nil) {
            case .replaceScreen:
                loaded = nil
                failure = error.localizedDescription
            case .reportOnly:
                actions.onLoadFailed(error.localizedDescription)
            }
        }
    }

    private func editing(_ actions: DetailActions) -> DetailActions {
        var wrapped = actions
        wrapped.onRename = { name in
            await actions.onRename(name)
            await load()
        }
        wrapped.onChangeCategory = { category in
            await actions.onChangeCategory(category)
            await load()
        }
        return wrapped
    }
}

struct DetailActions {
    var onLoadFailed: (String) -> Void = { _ in }
    var onBack: () -> Void = {}
    var onRename: (String?) async -> Void = { _ in }
    var onChangeCategory: (String?) async -> Void = { _ in }
    var onToggleReminder: (Bool) -> Void = { _ in }
    var onMarkCancelled: () -> Void = {}
}

struct DetailView: View {
    let payload: DetailPayload
    var actions = DetailActions()
    @State private var editing: Editing?

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
            .layoutPriority(1)
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
                .minimumScaleFactor(0.8)
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
