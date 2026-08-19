import SwiftUI

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

#Preview("Splash") {
    SplashView()
}
