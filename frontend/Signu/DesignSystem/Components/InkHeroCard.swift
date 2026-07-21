import SwiftUI

/// Ink-dark hero card container — subscription detail and connection detail
/// heroes. Content is injected; the card owns surface, radius and padding.
struct InkHeroCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(SignuColor.ink, in: RoundedRectangle(cornerRadius: SignuMetric.heroRadius, style: .continuous))
    }
}

/// Stat tile inside the ink hero: THIS YEAR / SINCE NOV 23 / LAST SYNCED…
struct HeroStatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Own label (not OverlineText): lighter kerning + strong shrink so
            // long labels like "SINCE SEP 25 · 2 RUNS" stay on one line.
            Text(label.uppercased())
                .font(SignuFont.font(12, .semibold, tabular: true))
                .kerning(0.5)
                .foregroundStyle(SignuColor.onInkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(value)
                .font(.signuStatValue)
                .foregroundStyle(SignuColor.onInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(SignuColor.inkTile, in: RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous))
    }
}

// Subscription-run heroes live in SubscriptionHeroCard (all four states
// previewed there). This preview only exercises the bare container + tiles.
#Preview("Container + stat tiles") {
    InkHeroCard {
        Text("Itaú")
            .font(.signuHeadline)
            .foregroundStyle(SignuColor.onInk)
            .padding(.bottom, 16)
        HStack(spacing: 12) {
            HeroStatTile(label: "Last synced", value: "Jul 12 · 08:14")
            HeroStatTile(label: "Consent expires", value: "Sep 28")
        }
    }
    .padding(SignuMetric.screenPadding)
    .background(SignuColor.paper)
}
