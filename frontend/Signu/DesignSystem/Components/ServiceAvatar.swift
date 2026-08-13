import SwiftUI

/// Monogram tile — tier 3 of the logo sourcing contract (the zero-data
/// fallback, and the only tier built at this stage). Colored rounded square
/// with the service's initial.
struct ServiceAvatar: View {
    let name: String
    var size: CGFloat = 44
    var color: Color?

    /// Optional so every preview, screenshot harness and test that renders a row
    /// without a store keeps working — and gets tier 3, which is a complete
    /// answer rather than a degraded one.
    @Environment(LogoStore.self) private var logos: LogoStore?

    // Verbatim first character — "iCloud+" keeps its lowercase "i" (21r).
    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1))
    }

    var body: some View {
        if let logo = logos?.image(forName: name) {
            mark(logo)
        } else {
            monogram
        }
    }

    /// Tier 1: the real mark, inside a neutral tile.
    ///
    /// The container is locked (v12) and does two jobs. It keeps the muted list
    /// calm — real logos arrive at full brand saturation and a row of naked marks
    /// reads as competing billboards — and it absorbs logo.dev's shape and
    /// background variance with zero per-merchant styling. Colour is kept because
    /// recognition is the entire point of fetching real logos; greyscale would pay
    /// the fetch complexity and throw away what it bought.
    private func mark(_ logo: Image) -> some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(SignuColor.surfaceBright)
            .frame(width: size, height: size)
            .overlay {
                logo
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
            }
            .overlay {
                // A hairline, because a near-white tile on the paper ground would
                // otherwise dissolve into it. v12 flagged the opposite case as an
                // open check — these tiles on the ink-dark detail hero — and this
                // is what keeps both readable without a second treatment.
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(SignuColor.hairline, lineWidth: 1)
            }
    }

    /// Tier 3: the zero-data fallback, and what every row rendered before logos
    /// existed.
    private var monogram: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(color ?? BrandPalette.color(for: name))
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(SignuFont.font(size * 0.45, .semibold))
                    .foregroundStyle(.white)
            }
    }
}

#Preview("Service avatars") {
    HStack(spacing: 12) {
        ServiceAvatar(name: "Netflix")
        ServiceAvatar(name: "Spotify")
        ServiceAvatar(name: "iCloud+")
        ServiceAvatar(name: "Globoplay", size: 56)
        ServiceAvatar(name: "Unknown Service")
    }
    .padding()
    .background(SignuColor.paper)
}
