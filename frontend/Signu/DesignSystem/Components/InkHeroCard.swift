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
            OverlineText(label, color: SignuColor.onInkSecondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SignuColor.onInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SignuColor.inkTile, in: RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous))
    }
}

#Preview("Detail hero") {
    InkHeroCard {
        HStack(alignment: .top, spacing: 14) {
            ServiceAvatar(name: "Netflix", size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("Netflix")
                    .font(.signuHeadline)
                    .foregroundStyle(SignuColor.onInk)
                Text("Monthly · Visa – 4821")
                    .font(.signuSubtitle)
                    .foregroundStyle(SignuColor.onInkSecondary)
            }
            Spacer()
            StatusChip(text: "Active", tone: .positive, onInk: true)
        }
        .padding(.bottom, 20)

        HStack(alignment: .firstTextBaseline) {
            Text("R$ 44,90")
                .font(.signuHero)
                .foregroundStyle(SignuColor.onInk)
            Text("/mo")
                .font(.signuBody)
                .foregroundStyle(SignuColor.onInkSecondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                OverlineText("Renews", color: SignuColor.onInkSecondary)
                Text("Jul 18 · in 5 days")
                    .font(.signuRowTitle)
                    .foregroundStyle(SignuColor.onInk)
            }
        }
        .padding(.bottom, 20)

        HStack(spacing: 12) {
            HeroStatTile(label: "This year", value: "R$ 289,30")
            HeroStatTile(label: "Since Nov 23", value: "R$ 1.312,70")
        }
    }
    .padding(SignuMetric.screenPadding)
    .background(SignuColor.paper)
}
