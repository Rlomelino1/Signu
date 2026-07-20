import SwiftUI

/// App shell: paper background, screen content, floating tab bar.
/// Screens land per the approval-gated plan; placeholders hold their slots.
struct RootView: View {
    /// Lets previews/screenshots open Home pre-scrolled (bottom-inset review).
    var homeScrollAnchor: UnitPoint = .top

    @State private var selectedTab = SignuTab.home
    @State private var tabBarState = TabBarState()
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

    init(homeScrollAnchor: UnitPoint = .top) {
        self.homeScrollAnchor = homeScrollAnchor
        #if DEBUG
        FontDiagnostics.runIfRequested()
        #endif
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
                    onSeeAll: { selectedTab = .subs }
                ), scrollAnchor: effectiveHomeAnchor)
            case .subs:
                PlaceholderScreen(title: "Subscriptions", note: "Coming in step 3")
            case .settings:
                PlaceholderScreen(title: "Settings", note: "Coming in step 6")
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
        #if DEBUG
        .onAppear(perform: runAutoHideDemoIfRequested)
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
