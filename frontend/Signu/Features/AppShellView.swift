import SwiftUI

struct AppShellView: View {
    let provider: SignuDataProviding
    var homeScrollAnchor: UnitPoint = .top
    var subsScrollAnchor: UnitPoint = .top
    var initialSubsFilter: SubsFilter = .all
    var onSignOut: () -> Void = {}
    var onSetPassword: () -> Void = {}

    @State private var selectedTab = SignuTab.home
    @State private var tabBarState = TabBarState()
    @State private var passwordLinkState = PasswordLinkState()
    @State private var showReview = false
    @State private var detailSubscriptionId: UUID?
    @State private var detailFixture: DetailPayload?
    @State private var settingsConnectionId: UUID?
    @State private var deleteScope: DeleteScopeBox?
    @State private var actionError: String?
    @State private var connectTarget: ConnectTarget?
    @State private var dataVersion = 0
    @State private var showSearch = false
    @State private var showCalendar = false
    @State private var suggestionCount = 0
    @State private var logos = LogoStore()
    @State private var avatars = AvatarStore()
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
                        onLoadFailed: { actionError = $0 },
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
                            onLoadFailed: { actionError = $0 },
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
                            onLoadFailed: { actionError = $0 },
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
                        onRestore: { id in
                            act { try await provider.setIgnored(subscriptionId: id, ignored: false) }
                        },
                        onDeleteAccount: {
                            Task {
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
            .id(dataVersion)

            SignuTabBar(selection: $selectedTab, suggestionCount: suggestionCount)
                .padding(.bottom, 8)
                .offset(y: !reduceMotion && tabBarState.hidden ? 170 : 0)
                .opacity(reduceMotion && tabBarState.hidden ? 0 : 1)
                .animation(.easeOut(duration: 0.25), value: tabBarState.hidden)
        }
        .environment(tabBarState)
        .environment(passwordLinkState)
        .environment(logos)
        .environment(avatars)
        .task {
            guard let catalog = try? await provider.brandCatalog() else { return }
            logos.adopt(catalog: catalog)
            await logos.prefetch()
        }
        .task(id: dataVersion) { await refreshSuggestionCount() }
        .task(id: dataVersion) {
            guard let profile = try? await provider.profile() else { return }
            await avatars.load(path: profile.avatarPath, using: provider)
        }
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
            guard !isShowing else { return }
            Task {
                let before = suggestionCount
                await refreshSuggestionCount()
                if suggestionCount != before { dataVersion += 1 }
            }
        }
        .onChange(of: selectedTab) {
            tabBarState.reset()
        }
        .fullScreenCover(isPresented: $showReview) {
            ReviewScreen(
                provider: provider,
                actions: ReviewActions(
                    onBack: { showReview = false },
                    onTrack: { runId, interval in
                        act { try await provider.confirmSuggestion(runId: runId, billingInterval: interval) }
                    },
                    onDismiss: { id in
                        act { try await provider.setIgnored(subscriptionId: id, ignored: true) }
                    },
                    onRemind: { id in
                        act { try await provider.setReminder(subscriptionId: id, remindBeforeDays: 2) }
                    }
                ),
                autoPresentIntervalForR4: reviewAutoR4
            )
            .environment(logos)
        }
        .fullScreenCover(item: $detailSubscriptionId) { id in
            DetailScreen(
                loader: { try await provider.detailPayload(subscriptionId: id) },
                actions: DetailActions(
                    onLoadFailed: { actionError = $0 },
                    onBack: { detailSubscriptionId = nil },
                    onRename: { name in
                        do {
                            try await provider.setNickname(subscriptionId: id, nickname: name)
                            dataVersion += 1
                        } catch {
                            actionError = error.localizedDescription
                        }
                    },
                    onChangeCategory: { category in
                        do {
                            try await provider.setCategory(subscriptionId: id, category: category)
                            dataVersion += 1
                        } catch {
                            actionError = error.localizedDescription
                        }
                    },
                    onToggleReminder: { on in
                        act {
                            try await provider.setReminder(
                                subscriptionId: id,
                                remindBeforeDays: on ? 2 : nil
                            )
                        }
                    },
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
        .fullScreenCover(item: $settingsConnectionId) { id in
            ConnectionDetailScreen(
                provider: provider,
                connectionId: id,
                onBack: { settingsConnectionId = nil },
                onReconnected: {
                    settingsConnectionId = nil
                    dataVersion += 1
                }
            )
            .environment(logos)
        }
        .connectBankCover(provider: provider, target: $connectTarget) { dataVersion += 1 }
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
                .environment(avatars)
                .presentationDetents([.height(460)])
                .presentationDragIndicator(.visible)
        }
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

struct DeleteScopeBox: Identifiable {
    let id = UUID()
    let scope: DeleteAccountScope
}

enum SignuDataProviderFactory {
    @MainActor
    static func make() -> SignuDataProviding {
        #if DEBUG
        if CommandLine.arguments.contains("--shell-nobank") {
            return MockDataProvider(scenario: .noBank)
        }
        if CommandLine.arguments.contains("--shell-fresh") {
            return MockDataProvider(scenario: .freshConnection)
        }
        if CommandLine.arguments.contains("--shell-suggestions") {
            return MockDataProvider(scenario: .suggestionsOnly)
        }
        if CommandLine.arguments.contains("--live-data") {
            return SupabaseDataProvider()
        }
        return MockDataProvider()
        #else
        return SupabaseDataProvider()
        #endif
    }
}

#Preview("App shell") {
    AppShellView(provider: MockDataProvider())
}
