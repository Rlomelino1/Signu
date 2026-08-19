import SwiftUI

struct SignuWordmark: View {
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
