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
    /// One piece of state for one presentation. It used to be two — a `Bool`
    /// plus the scope it needed — and the sheet raced them: it presented on the
    /// flag with the scope still nil, its `if let` failed, and 14a came up as an
    /// EMPTY sheet. Found by a UI test tapping the row and looking for the
    /// header, then reading the accessibility tree: a presented container with
    /// nothing in it. Every other presentation in this file is already
    /// item-driven, which is why none of them can do this.
    @State private var deleteScope: DeleteScopeBox?
    /// Set when one of the four Edge Function writes fails. See `act`.
    @State private var actionError: String?
    /// The connect flow, presented for both "add a bank" (nil id) and
    /// "re-authenticate this one" (a connection id). `ConnectTarget` exists
    /// because `.fullScreenCover(item:)` needs an Identifiable, and `UUID?`
    /// cannot express "present, with nothing selected".
    @State private var connectTarget: ConnectTarget?
    /// Bumped after a bank is connected. Connecting changes every screen at
    /// once — banks, cards, subscriptions, the hero number — so the tab is
    /// rebuilt rather than left showing the graph as it was before the link
    /// existed. Nothing else in the app invalidates this widely, because
    /// nothing else changes this much.
    @State private var dataVersion = 0
    /// The Subs tab's magnifier and Home's Calendar control — both designed into
    /// their screens and both, until now, buttons that opened nothing.
    @State private var showSearch = false
    @State private var showCalendar = false
    /// Drives the Subs tab dot (22a). Held here because the bar lives here, and
    /// refreshed at the two moments it can change: a trip through review, and any
    /// rebuild of the tab.
    @State private var suggestionCount = 0
    /// Owned by the shell so one cache serves every screen, and so the prefetch
    /// runs once per launch rather than once per row.
    @State private var logos = LogoStore()
    /// Owned here for the same two reasons as `logos`: one cache serves every
    /// surface that renders the picture, and the download happens once per launch
    /// rather than once per appearance.
    @State private var avatars = AvatarStore()
    /// Drives the edit-profile sheet (v47).
    @State private var editingProfile = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

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

            Group {
                switch selectedTab {
                case .home:
                    HomeScreen(provider: provider, actions: HomeActions(
                        // The needs-action banner's Fix (12b's other entry point):
                        // re-authenticating is the same widget opened on an existing
                        // item, so it is the same flow with an id.
                        onFixConnection: { connectTarget = ConnectTarget(connectionId: $0) },
                        onReview: { showReview = true },
                        onCalendar: { showCalendar = true },
                        onSeeAll: { selectedTab = .subs },
                        onSelectSubscription: { detailSubscriptionId = $0 },
                        onConnectBank: { connectTarget = ConnectTarget(connectionId: nil) }
                    ), scrollAnchor: effectiveHomeAnchor)
                case .subs:
                    #if DEBUG
                    SubsScreen(
                        provider: provider,
                        actions: SubsActions(
                            onSelectSubscription: { detailSubscriptionId = $0 },
                            onReviewSuggestion: { _ in showReview = true },
                            onSearch: { showSearch = true }
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
                            onReviewSuggestion: { _ in showReview = true },
                            onSearch: { showSearch = true }
                        ),
                        initialFilter: initialSubsFilter
                    )
                    #endif
                case .settings:
                    SettingsScreen(provider: provider, actions: SettingsActions(
                        onSelectBank: { settingsConnectionId = $0 },
                        onEditProfile: { editingProfile = true },
                        onConnectBank: { connectTarget = ConnectTarget(connectionId: nil) },
                        // Restore is `ignored = false` and nothing more: the run returns
                        // to `possible` and resurfaces in review, because it never left
                        // that state. SettingsView also hides the row locally, so the
                        // list reacts without waiting for the round trip.
                        onRestore: { id in
                            Task { try? await provider.setIgnored(subscriptionId: id, ignored: false) }
                        },
                        onDeleteAccount: {
                            Task {
                                // The scope IS the presentation: no scope, no
                                // sheet, rather than a sheet with nothing in it.
                                if let scope = try? await provider.deleteAccountScope() {
                                    deleteScope = DeleteScopeBox(scope: scope)
                                }
                            }
                        },
                        onSetPassword: onSetPassword,
                        onSignOut: onSignOut
                    ))
                }
            }
            // Connecting a bank rewrites every screen at once, so the tab is
            // rebuilt rather than left rendering the graph from before the link.
            .id(dataVersion)

            // Safari-style auto-hide (tab bar behavior contract): slides out
            // on downward scroll, back on any upward scroll or at content
            // end; crossfades instead when Reduce Motion is on.
            SignuTabBar(selection: $selectedTab, suggestionCount: suggestionCount)
                .padding(.bottom, 8)
                .offset(y: !reduceMotion && tabBarState.hidden ? 170 : 0)
                .opacity(reduceMotion && tabBarState.hidden ? 0 : 1)
                .animation(.easeOut(duration: 0.25), value: tabBarState.hidden)
        }
        .environment(tabBarState)
        .environment(passwordLinkState)
        // Re-applied on every presented surface below, not only here. A
        // full-screen cover does not reliably inherit a custom environment
        // object from its presenter — measured, not assumed: the Subs list
        // rendered real logos while the detail hero behind the same store kept
        // its monogram.
        .environment(logos)
        .environment(avatars)
        .task {
            // Reference data, loaded once, then every catalog domain is fetched —
            // including merchants this user has never heard of. That is the
            // privacy property rather than an oversight: a request set that
            // depends on the subscription list would disclose the subscription
            // list. See `LogoStore`.
            guard let catalog = try? await provider.merchantCatalog() else { return }
            logos.adopt(catalog: catalog)
            await logos.prefetch()
        }
        .task(id: dataVersion) { await refreshSuggestionCount() }
        // Keyed on dataVersion so this covers all three moments the path can
        // change: launch, an upload from the sheet below, and the foreground
        // re-read finding a picture set on another device.
        .task(id: dataVersion) {
            await avatars.load(path: try? await provider.profile().avatarPath, using: provider)
        }
        // Coming back to the app is the other moment the graph can have moved
        // without the app moving it: the sync runs at 15:30 UTC daily, and a
        // session left open across it renders yesterday's state indefinitely.
        //
        // The tab is rebuilt ONLY when the re-read actually found something.
        // Rebuilding unconditionally would cost the user their scroll position
        // every time they switched apps, to show them exactly what they were
        // already looking at.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                if (try? await provider.refresh()) == true {
                    dataVersion += 1
                }
                await refreshSuggestionCount()
            }
        }
        .onChange(of: showReview) { _, isShowing in
            // On the way OUT of review, where confirming and dismissing both
            // change the count. Cheap: the provider already holds the graph, so
            // this is a re-read of cached rows rather than a round trip.
            guard !isShowing else { return }
            Task {
                let before = suggestionCount
                await refreshSuggestionCount()
                // Home renders the count AND the headline that depends on it, so
                // a decision taken in review leaves the screen underneath stale —
                // "2 possible subscriptions" over a review screen with none left.
                // Rebuilt only when the number actually moved, so backing out
                // without deciding anything costs the user their scroll position
                // for nothing.
                if suggestionCount != before { dataVersion += 1 }
            }
        }
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
                    // The run id, not the subscription's: a suggestion IS a run
                    // sitting at `possible`, and confirming is lifting it out of
                    // that state. The interval is the R4 sheet's answer and nil
                    // for R3, whose cadence the engine measured.
                    onTrack: { runId, interval in
                        act { try await provider.confirmSuggestion(runId: runId, billingInterval: interval) }
                    },
                    onDismiss: { id in
                        Task { try? await provider.setIgnored(subscriptionId: id, ignored: true) }
                    },
                    // 22b's offer, taken right after a first confirmation. The
                    // same column write the detail toggle makes — on = 2 days,
                    // per the detail contract — so there is one way to be
                    // reminded and one place it is stored.
                    onRemind: { id in
                        Task { try? await provider.setReminder(subscriptionId: id, remindBeforeDays: 2) }
                    }
                ),
                autoPresentIntervalForR4: reviewAutoR4
            )
            .environment(logos)
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
                    // The overflow menu's two writes. Column writes inside
                    // Migration #1's grant, so they take the same shape as the
                    // reminder toggle rather than the four Edge Function actions:
                    // the sheet has already closed on the value the user chose,
                    // and the next read of this screen shows what actually landed.
                    onRename: { name in
                        try? await provider.setNickname(subscriptionId: id, nickname: name)
                        // The display name appears on Home and in the Subs list
                        // too, so the tab underneath is rebuilt rather than left
                        // showing what the subscription used to be called.
                        dataVersion += 1
                    },
                    onChangeCategory: { category in
                        try? await provider.setCategory(subscriptionId: id, category: category)
                        dataVersion += 1
                    },
                    onToggleReminder: { on in
                        Task {
                            try? await provider.setReminder(
                                subscriptionId: id,
                                remindBeforeDays: on ? 2 : nil
                            )
                        }
                    },
                    // Closes the detail on success, deliberately. The screen was
                    // built from a payload that now says the wrong thing —
                    // "renews in 3 days" above a run the user just cancelled —
                    // and the list it returns to re-reads. Leaving it open with
                    // stale state is the disagreement the invalidate-don't-edit
                    // rule exists to prevent (v29).
                    onMarkCancelled: {
                        act({ try await provider.markCancelled(subscriptionId: id) },
                            onSuccess: { detailSubscriptionId = nil })
                    }
                )
            )
            .environment(logos)
        }
        .fullScreenCover(item: $detailFixture) { fixture in
            DetailScreen(payload: fixture, actions: DetailActions(onBack: { detailFixture = nil }))
                .environment(logos)
        }
        // Connection detail (12b) — covers the tab bar; from a Settings bank row.
        .fullScreenCover(item: $settingsConnectionId) { id in
            ConnectionDetailScreen(
                provider: provider,
                connectionId: id,
                onBack: { settingsConnectionId = nil },
                // 12b runs the reconnect itself; this is what it reports back, so
                // Settings does not keep rendering the pre-reconnect chip.
                onReconnected: {
                    settingsConnectionId = nil
                    dataVersion += 1
                }
            )
            .environment(logos)
        }
        // Connect a bank (12d's CTA, Settings' row, Home's empty state) and
        // re-authenticate one (Home's banner). 12b's Reconnect presents the same
        // flow from there, because a cover cannot present a cover.
        .connectBankCover(provider: provider, target: $connectTarget) { dataVersion += 1 }
        // Search (Subs) and the renewal calendar (Home). Both cover the tab bar,
        // like every other pushed surface in this shell.
        .fullScreenCover(isPresented: $showSearch) {
            SearchScreen(
                provider: provider,
                onSelectSubscription: { id in
                    showSearch = false
                    detailSubscriptionId = id
                },
                onReviewSuggestion: { _ in
                    showSearch = false
                    showReview = true
                },
                onBack: { showSearch = false }
            )
            .environment(logos)
        }
        .fullScreenCover(isPresented: $showCalendar) {
            CalendarScreen(
                provider: provider,
                onSelectSubscription: { id in
                    showCalendar = false
                    detailSubscriptionId = id
                },
                onBack: { showCalendar = false }
            )
            .environment(logos)
        }
        .sheet(item: $deleteScope) { box in
            // Tier (a): one auth.admin.deleteUser() call behind the
            // `delete-account` function, and the cascade takes the rest. The
            // sign-out happens only after it returns — ending the session first
            // would look identical to the user and leave the account standing.
            DeleteAccountSheet(scope: box.scope, onDelete: {
                act({ try await provider.deleteAccount() },
                    onSuccess: {
                        deleteScope = nil
                        onSignOut()
                    })
            })
            .presentationDetents([.height(560)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $editingProfile) {
            EditProfileSheet(provider: provider, onChanged: { dataVersion += 1 })
                // Re-applied here for the reason the `logos` comment above records:
                // a presented surface does not reliably inherit a custom
                // environment object, and the sheet renders the same avatar.
                .environment(avatars)
                .presentationDetents([.height(460)])
                .presentationDragIndicator(.visible)
        }
        // The four Edge Function writes change state no screen is showing, so a
        // failure has nowhere to be noticed. The message is the server's own
        // ("R4 confirmation must state monthly or annual"), not a generic
        // apology, because it is the only thing that says what to do next.
        .alert(
            "That didn't go through",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        #if DEBUG
        .onAppear {
            runAutoHideDemoIfRequested()
            if CommandLine.arguments.contains("--shell-review")
                || CommandLine.arguments.contains("--review-r4-sheet") { showReview = true }
        }
        #endif
    }

    private func refreshSuggestionCount() async {
        suggestionCount = (try? await provider.reviewPayload().suggestions.count) ?? 0
    }

    /// Runs one of the four writes the client is not granted, and surfaces what
    /// happens if it fails.
    ///
    /// Deliberately not `try?`, which is right for the two column writes beside
    /// it: a reminder toggle has already moved on screen and the next read
    /// corrects it either way. These four confirm a suggestion, end a run, or
    /// delete data — the screen cannot show whether they landed, so swallowing
    /// the error would leave the user believing something that did not happen.
    ///
    /// `onSuccess` runs only after the await returns, which is the whole point
    /// at the delete-account call site: signing out first would look identical
    /// and leave the account alive.
    private func act(
        _ work: @escaping () async throws -> Void,
        onSuccess: @escaping () -> Void = {}
    ) {
        Task {
            do {
                try await work()
                onSuccess()
            } catch {
                actionError = error.localizedDescription
            }
        }
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

/// Carries 14a's scope counts into the sheet. A box rather than making
/// `DeleteAccountScope` itself `Identifiable`: the scope is a value read from
/// the provider, and inventing an identity on it to satisfy a presentation API
/// would put a UI concern inside a payload.
struct DeleteScopeBox: Identifiable {
    let id = UUID()
    let scope: DeleteAccountScope
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
        if CommandLine.arguments.contains("--shell-suggestions") {
            return MockDataProvider(scenario: .suggestionsOnly)
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
