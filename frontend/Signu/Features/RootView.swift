import SwiftUI

/// App shell: paper background, screen content, floating tab bar.
/// Screens land per the approval-gated plan; placeholders hold their slots.
struct RootView: View {
    /// Lets previews/screenshots open Home pre-scrolled (bottom-inset review).
    var homeScrollAnchor: UnitPoint = .top
    /// Same, for the Subs tab — previews render tab screens inside the shell
    /// (tab bar overlaid) so hide/show behavior and bottom clearance are
    /// reviewable (tab bar contract v13).
    var subsScrollAnchor: UnitPoint = .top
    var initialSubsFilter: SubsFilter = .all

    @State private var selectedTab = SignuTab.home
    @State private var tabBarState = TabBarState()
    @State private var showReview = false
    @State private var detailSubscriptionId: UUID?
    @State private var detailFixture: DetailPayload?
    @State private var settingsConnectionId: UUID?
    @State private var showDelete = false
    @State private var deleteScope: DeleteAccountScope?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let provider: SignuDataProviding = {
        #if DEBUG
        // Shell with the short empty-state content, for auto-hide review.
        if CommandLine.arguments.contains("--shell-nobank") {
            return MockDataProvider(scenario: .noBank)
        }
        #endif
        return MockDataProvider()
    }()

    // Screenshot runs pass --home-bottom to review the bottom inset in
    // context (shell + tab bar), pre-scrolled to the end.
    private var effectiveHomeAnchor: UnitPoint {
        #if DEBUG
        if CommandLine.arguments.contains("--home-bottom") { return .bottom }
        #endif
        return homeScrollAnchor
    }

    init(homeScrollAnchor: UnitPoint = .top, initialTab: SignuTab = .home,
         initialSubsFilter: SubsFilter = .all, subsScrollAnchor: UnitPoint = .top) {
        self.homeScrollAnchor = homeScrollAnchor
        self.initialSubsFilter = initialSubsFilter
        self.subsScrollAnchor = subsScrollAnchor
        var tab = initialTab
        #if DEBUG
        if CommandLine.arguments.contains("--shell-subs") { tab = .subs }
        if CommandLine.arguments.contains("--shell-settings") { tab = .settings }
        FontDiagnostics.runIfRequested()
        #endif
        self._selectedTab = State(initialValue: tab)
    }

    var body: some View {
        #if DEBUG
        // Screenshot harnesses: `simctl launch … pro.sinatra.signu --hero-states[=0,1]`
        if let heroArg = CommandLine.arguments.first(where: { $0.hasPrefix("--hero-states") }) {
            let indices = heroArg.split(separator: "=").dropFirst().first
                .map { $0.split(separator: ",").compactMap { Int($0) } } ?? []
            if indices.isEmpty {
                HeroStatesGallery()
            } else {
                HeroStatesGallery(indices: indices)
            }
        } else if CommandLine.arguments.contains("--gallery-center") {
            DesignSystemGallery(anchor: .center)
        } else if CommandLine.arguments.contains("--gallery-bottom") {
            DesignSystemGallery(anchor: .bottom)
        } else if CommandLine.arguments.contains("--gallery") {
            DesignSystemGallery()
        } else if CommandLine.arguments.contains("--home-watching") {
            HomeScreen(provider: MockDataProvider(scenario: .freshConnection))
        } else if CommandLine.arguments.contains("--home-nobank") {
            HomeScreen(provider: MockDataProvider(scenario: .noBank))
        } else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--detail=") }) {
            DetailDebugView(
                name: String(arg.dropFirst("--detail=".count)),
                bottom: CommandLine.arguments.contains("--detail-bottom")
            )
        } else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--settings=") }) {
            SettingsDebugView(name: String(arg.dropFirst("--settings=".count)))
        } else {
            shell
        }
        #else
        shell
        #endif
    }

    private var shell: some View {
        ZStack(alignment: .bottom) {
            SignuColor.paper.ignoresSafeArea()

            switch selectedTab {
            case .home:
                HomeScreen(provider: provider, actions: HomeActions(
                    onReview: { showReview = true },
                    onSeeAll: { selectedTab = .subs },
                    onSelectSubscription: { detailSubscriptionId = $0 }
                ), scrollAnchor: effectiveHomeAnchor)
            case .subs:
                #if DEBUG
                SubsScreen(
                    provider: provider,
                    actions: SubsActions(
                        onSelectSubscription: { detailSubscriptionId = $0 },
                        onReviewSuggestion: { _ in showReview = true }
                    ),
                    initialFilter: CommandLine.arguments.contains("--subs-inactive") ? .inactive : initialSubsFilter,
                    initialSortByCost: CommandLine.arguments.contains("--subs-cost"),
                    scrollAnchor: CommandLine.arguments.contains("--subs-bottom") ? .bottom : subsScrollAnchor
                )
                #else
                SubsScreen(
                    provider: provider,
                    actions: SubsActions(
                        onSelectSubscription: { detailSubscriptionId = $0 },
                        onReviewSuggestion: { _ in showReview = true }
                    ),
                    initialFilter: initialSubsFilter
                )
                #endif
            case .settings:
                SettingsScreen(provider: provider, actions: SettingsActions(
                    onSelectBank: { settingsConnectionId = $0 },
                    onDeleteAccount: {
                        Task {
                            deleteScope = try? await provider.deleteAccountScope()
                            showDelete = true
                        }
                    }
                ))
            }

            // Safari-style auto-hide (tab bar behavior contract): slides out
            // on downward scroll, back on any upward scroll or at content
            // end; crossfades instead when Reduce Motion is on.
            SignuTabBar(selection: $selectedTab)
                .padding(.bottom, 8)
                .offset(y: !reduceMotion && tabBarState.hidden ? 170 : 0)
                .opacity(reduceMotion && tabBarState.hidden ? 0 : 1)
                .animation(.easeOut(duration: 0.25), value: tabBarState.hidden)
        }
        .environment(tabBarState)
        .onChange(of: selectedTab) {
            tabBarState.reset()
        }
        // Review (9a) covers the tab bar — reached from Home's Review pill
        // and Subs' SUGGESTED rows.
        .fullScreenCover(isPresented: $showReview) {
            ReviewScreen(
                provider: provider,
                actions: ReviewActions(onBack: { showReview = false }),
                autoPresentIntervalForR4: reviewAutoR4
            )
        }
        // Subscription detail — covers the tab bar; from any row tap.
        .fullScreenCover(item: $detailSubscriptionId) { id in
            DetailScreen(
                loader: { try? await provider.detailPayload(subscriptionId: id) },
                actions: DetailActions(onBack: { detailSubscriptionId = nil })
            )
        }
        .fullScreenCover(item: $detailFixture) { fixture in
            DetailScreen(payload: fixture, actions: DetailActions(onBack: { detailFixture = nil }))
        }
        // Connection detail (12b) — covers the tab bar; from a Settings bank row.
        .fullScreenCover(item: $settingsConnectionId) { id in
            ConnectionDetailScreen(provider: provider, connectionId: id, onBack: { settingsConnectionId = nil })
        }
        .sheet(isPresented: $showDelete) {
            if let deleteScope {
                DeleteAccountSheet(scope: deleteScope, onDelete: { showDelete = false })
                    .presentationDetents([.height(560)])
                    .presentationDragIndicator(.visible)
            }
        }
        #if DEBUG
        .onAppear {
            runAutoHideDemoIfRequested()
            if CommandLine.arguments.contains("--shell-review")
                || CommandLine.arguments.contains("--review-r4-sheet") { showReview = true }
        }
        #endif
    }

    private var reviewAutoR4: Bool {
        #if DEBUG
        return CommandLine.arguments.contains("--review-r4-sheet")
        #else
        return false
        #endif
    }

    #if DEBUG
    /// `--autohide-demo`: drives the real UIScrollView so the full
    /// preference → TabBarState pipeline runs without touch injection.
    /// Sequence: down (hide) → nudge up (reveal) → bottom (reveal).
    private func runAutoHideDemoIfRequested() {
        guard CommandLine.arguments.contains("--autohide-demo") else { return }
        func scrollTo(_ y: CGFloat) {
            guard let scroll = Self.firstScrollView() else { return }
            let maxY = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
            let target = min(max(y, -scroll.adjustedContentInset.top), maxY)
            scroll.setContentOffset(CGPoint(x: 0, y: target), animated: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { scrollTo(500) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { scrollTo(430) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { scrollTo(.greatestFiniteMagnitude) }
    }

    private static func firstScrollView() -> UIScrollView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        func find(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            for subview in view.subviews {
                if let found = find(in: subview) { return found }
            }
            return nil
        }
        for window in windows {
            if let found = find(in: window) { return found }
        }
        return nil
    }
    #endif
}

#if DEBUG
/// Screenshot harness for detail variants: `--detail=<name>` where name is
/// netflix / globoplay / spotify / amazon / cancelled / max, plus optional
/// `--detail-bottom` to open scrolled to the run start (21l).
private struct DetailDebugView: View {
    let name: String
    let bottom: Bool

    private let provider = MockDataProvider()
    private let serviceNames = [
        "netflix": "Netflix", "globoplay": "Globoplay",
        "spotify": "Spotify", "amazon": "Amazon Prime", "mubi": "MUBI",
    ]

    var body: some View {
        let anchor: UnitPoint = bottom ? .bottom : .top
        switch name {
        case "cancelled":
            let (sub, runs, charges) = MockDataProvider.demoCancelledTrailing()
            DetailScreen(payload: provider.detailPayload(subscription: sub, runs: runs, charges: charges), scrollAnchor: anchor)
        case "max":
            let (sub, runs, charges) = MockDataProvider.demoMax()
            DetailScreen(payload: provider.detailPayload(subscription: sub, runs: runs, charges: charges), scrollAnchor: anchor)
        default:
            DetailScreen(loader: {
                let service = serviceNames[name] ?? "Netflix"
                guard let sub = (try? await provider.subscriptions())?.first(where: { $0.serviceName == service })
                else { return nil }
                return try? await provider.detailPayload(subscriptionId: sub.id)
            }, scrollAnchor: anchor)
        }
    }
}
#endif

#if DEBUG
/// Screenshot harness for settings sub-screens: `--settings=<name>` where
/// name is connection-itau / connection-nubank / connection-bradesco /
/// attributed-itau / remove / delete.
private struct SettingsDebugView: View {
    let name: String
    private let provider = MockDataProvider()
    @State private var deleteScope: DeleteAccountScope?

    var body: some View {
        switch name {
        case "connection-itau", "connection-nubank", "connection-bradesco":
            ConnectionDetailScreen(provider: provider, connectionId: connId(String(name.dropFirst("connection-".count))))
        case "attributed-itau":
            AttributedSubsScreen(provider: provider, connectionId: connId("itau"))
        case "remove":
            SignuColor.paper.ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    RemoveBankSheet(institutionName: "Itaú", count: 11)
                        .presentationDetents([.height(560)])
                        .presentationDragIndicator(.visible)
                }
        case "delete":
            SignuColor.paper.ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    Group {
                        if let deleteScope {
                            DeleteAccountSheet(scope: deleteScope)
                                .presentationDetents([.height(560)])
                                .presentationDragIndicator(.visible)
                        } else {
                            Color.clear
                        }
                    }
                    .task { deleteScope = try? await provider.deleteAccountScope() }
                }
        default:
            SettingsScreen(provider: provider)
        }
    }

    private func connId(_ key: String) -> UUID {
        let map = ["itau": "Itaú", "nubank": "Nubank", "bradesco": "Bradesco"]
        return provider.connectionList.first { $0.institutionName == (map[key] ?? "Itaú") }?.id ?? UUID()
    }
}
#endif

private struct PlaceholderScreen: View {
    let title: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.signuScreenTitle)
                .foregroundStyle(SignuColor.textPrimary)
            Text(note)
                .font(.signuBody)
                .foregroundStyle(SignuColor.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SignuMetric.screenPadding)
    }
}

#Preview {
    RootView()
}
