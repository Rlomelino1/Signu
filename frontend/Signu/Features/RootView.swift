import SwiftUI

/// App shell: paper background, screen content, floating tab bar.
/// Screens land per the approval-gated plan; placeholders hold their slots.
struct RootView: View {
    @State private var selectedTab = SignuTab.home

    private let provider: SignuDataProviding = MockDataProvider()

    var body: some View {
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
