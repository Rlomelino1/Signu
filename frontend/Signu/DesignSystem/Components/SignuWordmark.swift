import SwiftUI

/// The Signu wordmark — ink tile + name, exactly as 16a's upper zone renders
/// it. Extracted so three surfaces can share one definition:
///
/// 1. `WelcomeView` (16a), which owns the locked treatment,
/// 2. `SplashView`, so `.restoring → .unauthenticated` does not move it,
/// 3. `LaunchScreen.storyboard`, a static copy of the same geometry — so
///    there is no seam between the launch image and `SplashView` either.
///
/// A change here must be mirrored in the storyboard; the constants below are
/// what it duplicates.
struct SignuWordmark: View {
    /// Distance from the top of the content area to the tile — 16a's value.
    /// The splash and the launch storyboard both key off this.
    static let topPadding: CGFloat = 14
    static let tileSize: CGFloat = 64
    static let tileRadius: CGFloat = 18
    static let pointSize: CGFloat = 32
    static let gap: CGFloat = 8

    var body: some View {
        VStack(spacing: Self.gap) {
            RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous)
                .fill(SignuColor.ink)
                .frame(width: Self.tileSize, height: Self.tileSize)
                .overlay {
                    Text("S")
                        .font(SignuFont.font(Self.pointSize, .bold))
                        .foregroundStyle(SignuColor.onInk)
                }
            Text("Signu")
                .font(SignuFont.font(Self.pointSize, .bold))
                .foregroundStyle(SignuColor.textPrimary)
        }
    }
}

#Preview("Wordmark") {
    VStack(spacing: 0) {
        SignuWordmark().padding(.top, SignuWordmark.topPadding)
        Spacer()
    }
    .frame(maxWidth: .infinity)
    .background(SignuColor.paper)
}
