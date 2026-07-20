import SwiftUI

/// App shell: paper background, screen content, floating tab bar.
/// Screens land per the approval-gated plan; placeholders hold their slots.
struct RootView: View {
    /// Lets previews/screenshots open Home pre-scrolled (bottom-inset review).
    var homeScrollAnchor: UnitPoint = .top

    @State private var selectedTab = SignuTab.home

    private let provider: SignuDataProviding = MockDataProvider()

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

            SignuTabBar(selection: $selectedTab)
                .padding(.bottom, 8)
        }
    }
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
