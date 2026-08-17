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

    /// Tier 1: the real mark, filling the tile.
    ///
    /// The container is still doing two of its three jobs (v12): it absorbs
    /// logo.dev's background variance, and colour is kept because recognition is the
    /// entire point of fetching real logos.
    ///
    /// **What changed (v57): the mark fills the tile instead of sitting inside an
    /// 18% inset.** v12 added that padding to keep a list of real logos calm rather
    /// than reading as competing billboards. That was a real concern and it lost to a
    /// plainer one: logo.dev returns square icons that already carry their own
    /// padding and background, so ours stacked on top and produced a small mark
    /// floating in a near-white square — the tile looked unfinished rather than calm.
    ///
    /// `scaledToFill` with an explicit frame and clip, not `scaledToFit` with the
    /// padding removed. Every image logo.dev serves here is square (verified: 128×128
    /// across the catalog), so for real data the two are identical — but a future
    /// non-square source should fill and be clipped by the tile's own shape rather
    /// than letterbox inside it, which is the request this implements.
    private func mark(_ logo: Image) -> some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(SignuColor.surfaceBright)
            .frame(width: size, height: size)
            .overlay {
                logo
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
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
