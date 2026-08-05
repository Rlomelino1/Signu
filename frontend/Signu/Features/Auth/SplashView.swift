import SwiftUI

/// Cold-launch splash, held while the session restores (`.restoring`).
///
/// Wordmark on the app background, **no spinner**: restore is a keychain read
/// in the common case, and a spinner would advertise a wait that isn't there.
/// The wordmark uses 16a's treatment and position, so `.restoring →
/// .unauthenticated` reveals the carousel and CTA stack underneath a mark that
/// never moves. The launch storyboard matches the same geometry, so the seam
/// on the other side — launch image → this view — is gone too.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 0) {
            SignuWordmark()
                .padding(.top, SignuWordmark.topPadding)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(SignuColor.paper)
    }
}

// Review on 17 Pro and 17 Pro Max via the canvas device picker (v15) — the
// wordmark is safe-area-relative, so both notch heights matter here.
#Preview("Splash") {
    SplashView()
}
