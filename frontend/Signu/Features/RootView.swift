import SwiftUI

/// App shell: paper background, screen content, floating tab bar.
/// Screens land per the approval-gated plan; placeholders hold their slots.
struct RootView: View {
    @State private var selectedTab = SignuTab.home

    private let provider: SignuDataProviding = MockDataProvider()

    init() {
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
                PlaceholderScreen(title: "Home", note: "Coming in step 2")
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
