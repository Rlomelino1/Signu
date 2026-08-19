import SwiftUI

enum SignuTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case subs = "Subs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house"
        case .subs: "rectangle.stack"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct SignuTabBar: View {
    @Binding var selection: SignuTab
    var suggestionCount = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SignuTab.allCases) { tab in
                tabItem(tab)
            }
        }
        .padding(6)
        .background(SignuColor.surface, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }

    private func tabItem(_ tab: SignuTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .medium))
                    .overlay(alignment: .topTrailing) {
                        if tab == .subs && suggestionCount > 0 {
                            Circle()
                                .fill(SignuColor.green)
                                .frame(width: 8, height: 8)
                                .offset(x: 6, y: -3)
                        }
                    }
                Text(tab.rawValue)
                    .font(SignuFont.font(13, .medium))
            }
            .foregroundStyle(selection == tab ? SignuColor.textPrimary : SignuColor.textSecondary)
            .frame(width: 86, height: 62)
            .background {
                if selection == tab {
                    Capsule().fill(SignuColor.sunken.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityValue(tab == .subs && suggestionCount > 0 ? "\(suggestionCount) to review" : "")
    }
}

#Preview("Tab bar") {
    struct Host: View {
        @State private var tab = SignuTab.home
        var body: some View {
            VStack {
                Spacer()
                SignuTabBar(selection: $tab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SignuColor.paper)
        }
    }
    return Host()
}
