import SwiftUI

/// The authenticated app: paper background, tab screens, and the floating
/// capsule bar with its Safari-style auto-hide (tab bar contract v13).
///
/// Extracted from `RootView`, which is now only the auth gate. This is what
/// owns the bar, so it is also what tab-screen previews render inside — which
/// was always the intent of the v13 "previews render inside the shell"
/// requirement.
///
/// The `provider` is injected rather than constructed here: the gate boundary
/// is the provider boundary, so `RootView` builds one on entry to
/// `.authenticated` and drops it on exit. Nothing user-scoped outlives a
/// sign-out.
struct AppShellView: View {
    let provider: SignuDataProviding
    /// Lets previews/screenshots open Home pre-scrolled (bottom-inset review).
    var homeScrollAnchor: UnitPoint = .top
    /// Same, for the Subs tab.
    var subsScrollAnchor: UnitPoint = .top
    var initialSubsFilter: SubsFilter = .all
    /// Both exits (Settings' v19 sign-out row and 14a's delete confirmation)
    /// call this; the gate turns it into a root swap back to `WelcomeFlow`.
    var onSignOut: () -> Void = {}
    /// v19's password row sends 17d's reset link. Supplied from above rather than
    /// reached from here, exactly as `onSignOut` is: the shell holds a data
    /// provider, and the session deliberately never crosses that boundary.
    var onSetPassword: () -> Void = {}

    @State private var selectedTab = SignuTab.home
    @State private var tabBarState = TabBarState()
    /// Lives here, not in Settings: the `switch` below destroys the branch it is
    /// not rendering, and v19's resend cooldown must survive a trip to Home.
    @State private var passwordLinkState = PasswordLinkState()
    @State private var showReview = false
    @State private var detailSubscriptionId: UUID?
    @State private var detailFixture: DetailPayload?
    @State private var settingsConnectionId: UUID?
    @State private var showDelete = false
    @State private var deleteScope: DeleteAccountScope?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(provider: SignuDataProviding,
         homeScrollAnchor: UnitPoint = .top,
         initialTab: SignuTab = .home,
         initialSubsFilter: SubsFilter = .all,
         subsScrollAnchor: UnitPoint = .top,
         onSignOut: @escaping () -> Void = {},
         onSetPassword: @escaping () -> Void = {}) {
        self.provider = provider
        self.homeScrollAnchor = homeScrollAnchor
        self.initialSubsFilter = initialSubsFilter
        self.subsScrollAnchor = subsScrollAnchor
        self.onSignOut = onSignOut
        self.onSetPassword = onSetPassword
        var tab = initialTab
        #if DEBUG
        if CommandLine.arguments.contains("--shell-subs") { tab = .subs }
        if CommandLine.arguments.contains("--shell-settings") { tab = .settings }
        #endif
        self._selectedTab = State(initialValue: tab)
    }

    // Screenshot runs pass --home-bottom to review the bottom inset in
    // context (shell + tab bar), pre-scrolled to the end.
    private var effectiveHomeAnchor: UnitPoint {
        #if DEBUG
        if CommandLine.arguments.contains("--home-bottom") { return .bottom }
        #endif
        return homeScrollAnchor
    }

    var body: some View {
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
                    // Restore is `ignored = false` and nothing more: the run returns
                    // to `possible` and resurfaces in review, because it never left
                    // that state. SettingsView also hides the row locally, so the
                    // list reacts without waiting for the round trip.
                    onRestore: { id in
                        Task { try? await provider.setIgnored(subscriptionId: id, ignored: false) }
                    },
                    onDeleteAccount: {
                        Task {
                            deleteScope = try? await provider.deleteAccountScope()
                            showDelete = true
                        }
                    },
                    onSetPassword: onSetPassword,
                    onSignOut: onSignOut
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
        .environment(passwordLinkState)
        .onChange(of: selectedTab) {
            tabBarState.reset()
        }
        // Review (9a) covers the tab bar — reached from Home's Review pill
        // and Subs' SUGGESTED rows.
        .fullScreenCover(isPresented: $showReview) {
            ReviewScreen(
                provider: provider,
                actions: ReviewActions(
                    onBack: { showReview = false },
                    // onTrack is deliberately still unwired — see the note on
                    // SignuDataProviding's write section. Confirming a suggestion
                    // writes subscription_run.status and subscription.identification,
                    // and `authenticated` holds no UPDATE grant on either. It needs
                    // an Edge Function, not a method here.
                    onDismiss: { id in
                        Task { try? await provider.setIgnored(subscriptionId: id, ignored: true) }
                    }
                ),
                autoPresentIntervalForR4: reviewAutoR4
            )
        }
        // Subscription detail — covers the tab bar; from any row tap.
        .fullScreenCover(item: $detailSubscriptionId) { id in
            DetailScreen(
                loader: { try? await provider.detailPayload(subscriptionId: id) },
                actions: DetailActions(
                    onBack: { detailSubscriptionId = nil },
                    // On = 2 days, per the detail contract; off writes NULL, because
                    // the nullable column is the switch. `try?` because the toggle
                    // has already shown the new state: a thrown error here would
                    // have nowhere to render, and the next read shows the truth.
                    onToggleReminder: { on in
                        Task {
                            try? await provider.setReminder(
                                subscriptionId: id,
                                remindBeforeDays: on ? 2 : nil
                            )
                        }
                    }
                )
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
                // Real deletion is an Edge Function that doesn't exist yet
                // (tier (a): one auth.admin.deleteUser() call). Until it does,
                // confirming ends the session — the honest local half of the
                // action, and never a no-op that looks like success.
                DeleteAccountSheet(scope: deleteScope, onDelete: {
                    showDelete = false
                    onSignOut()
                })
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

/// Builds the data provider for a signed-in session. Called on entry to
/// `.authenticated` and dropped on exit: the real provider will need a
/// `user_id`, and stale rows must not survive a sign-out.
enum SignuDataProviderFactory {
    @MainActor
    static func make() -> SignuDataProviding {
        #if DEBUG
        // Shell with the short empty-state content, for auto-hide review.
        if CommandLine.arguments.contains("--shell-nobank") {
            return MockDataProvider(scenario: .noBank)
        }
        if CommandLine.arguments.contains("--shell-fresh") {
            return MockDataProvider(scenario: .freshConnection)
        }
        // Opt IN to live data in Debug, rather than opting out. Every existing
        // screenshot harness and preview keeps its deterministic mock dataset
        // without being touched, and a developer sees real rows only by asking:
        //   simctl launch … pro.sinatra.signu --live-data
        if CommandLine.arguments.contains("--live-data") {
            return SupabaseDataProvider()
        }
        return MockDataProvider()
        #else
        // Release reads the real thing. Mirrors how `SignuApp.sessionProvider()`
        // splits, so the two never disagree about which world a build is in.
        return SupabaseDataProvider()
        #endif
    }
}

#Preview("App shell") {
    AppShellView(provider: MockDataProvider())
}
