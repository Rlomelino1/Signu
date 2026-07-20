import SwiftUI

/// Light card container for row groups and standalone cards.
struct SignuCard<Content: View>: View {
    var background: Color = SignuColor.surface
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(background, in: RoundedRectangle(cornerRadius: SignuMetric.cardRadius, style: .continuous))
    }
}

/// Vertical stack of rows separated by hairlines, wrapped in a card.
/// Mirrors the mockups' grouped lists (home "Coming up", subs groups, settings).
struct SignuListCard<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    var background: Color = SignuColor.surface
    @ViewBuilder var row: (Data.Element) -> Row

    var body: some View {
        SignuCard(background: background) {
            VStack(spacing: 0) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                    row(element)
                    if index < data.count - 1 {
                        Rectangle()
                            .fill(SignuColor.hairline)
                            .frame(height: 1)
                            .padding(.leading, SignuMetric.rowPaddingH)
                    }
                }
            }
        }
    }
}

/// Standard row: avatar · title/subtitle · trailing value/detail.
/// Subtitles and trailing lines accept styled Text so callers can carry
/// state color (overdue red, suggestion green) without new row variants.
struct SignuRow<Leading: View>: View {
    let title: String
    var subtitle: Text?
    var trailingTitle: Text?
    var trailingSubtitle: Text?
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.signuRowTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                if let subtitle {
                    subtitle
                        .font(SignuFont.font(14))
                        .foregroundStyle(SignuColor.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let trailingTitle {
                    trailingTitle
                        .font(.signuRowTitle)
                        .foregroundStyle(SignuColor.textPrimary)
                }
                if let trailingSubtitle {
                    trailingSubtitle
                        .font(.signuSubtitle)
                        .foregroundStyle(SignuColor.textSecondary)
                }
            }
        }
        .padding(.vertical, SignuMetric.rowPaddingV)
        .padding(.horizontal, SignuMetric.rowPaddingH)
    }
}

#Preview("List card") {
    struct Item: Identifiable {
        let id = UUID()
        let name: String
        let sub: String
        let amount: String
        let date: String
    }
    let items = [
        Item(name: "Spotify", sub: "Monthly · Master 7730", amount: "R$ 21,90", date: "Jul 15"),
        Item(name: "Netflix", sub: "Monthly · Visa 4821", amount: "R$ 44,90", date: "Jul 18"),
        Item(name: "iCloud+", sub: "Monthly · Master 7730", amount: "R$ 14,90", date: "Jul 22"),
    ]
    return SignuListCard(data: items) { item in
        SignuRow(
            title: item.name,
            subtitle: Text(item.sub),
            trailingTitle: Text(item.amount),
            trailingSubtitle: Text(item.date)
        ) {
            ServiceAvatar(name: item.name)
        }
    }
    .padding(SignuMetric.screenPadding)
    .background(SignuColor.paper)
}
