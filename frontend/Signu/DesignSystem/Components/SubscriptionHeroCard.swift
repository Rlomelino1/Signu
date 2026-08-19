import SwiftUI

struct SubscriptionHeroCard: View {
    enum DateSlot {
        case renews(String)
        case expected(String)
        case paidThrough(String)

        var label: String {
            switch self {
            case .renews: "Renews"
            case .expected: "Expected"
            case .paidThrough: "Paid through"
            }
        }

        var value: String {
            switch self {
            case .renews(let value), .expected(let value), .paidThrough(let value): value
            }
        }

        var isAlert: Bool {
            if case .expected = self { return true }
            return false
        }

        var isDead: Bool {
            if case .paidThrough = self { return true }
            return false
        }
    }

    let serviceName: String
    let subtitle: String
    let statusText: String
    let statusTone: StatusChip.Tone
    let amount: String
    var unit: String? = "/mo"
    let dateSlot: DateSlot
    let stats: [(label: String, value: String)]

    var body: some View {
        InkHeroCard {
            HStack(alignment: .center, spacing: 12) {
                ServiceAvatar(name: serviceName, size: 46, onInk: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(serviceName)
                        .font(.signuHeadline)
                        .foregroundStyle(SignuColor.onInk)
                        .lineLimit(1)
                    Text(subtitle.signuNonBreaking)
                        .font(SignuFont.font(13.5))
                        .foregroundStyle(SignuColor.onInkSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusChip(text: statusText, tone: statusTone, onInk: true)
                    .fixedSize()
            }
            .padding(.bottom, 16)

            amountAndDate
                .padding(.bottom, 16)

            HStack(spacing: 12) {
                ForEach(stats.indices, id: \.self) { index in
                    HeroStatTile(label: stats[index].label, value: stats[index].value)
                }
            }
        }
    }

    @ViewBuilder
    private var amountAndDate: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                amountPair
                Spacer(minLength: 8)
                dateBlock(.trailing)
            }
            VStack(alignment: .leading, spacing: 10) {
                amountPair
                dateBlock(.leading)
            }
        }
    }

    private var amountPair: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(amount)
                .font(.signuHeroCompact)
                .foregroundStyle(SignuColor.onInk.opacity(dateSlot.isDead ? 0.72 : 1))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let unit {
                Text(unit)
                    .font(.signuSubtitle)
                    .foregroundStyle(SignuColor.onInkSecondary)
            }
        }
    }

    private func dateBlock(_ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            OverlineText(
                dateSlot.label,
                color: dateSlot.isAlert ? SignuColor.redOnInk : SignuColor.onInkSecondary
            )
            Text(dateSlot.value)
                .font(.signuSubtitleEmphasis)
                .foregroundStyle(dateSlot.isAlert ? SignuColor.redOnInk : SignuColor.onInk)
                .lineLimit(1)
        }
        .fixedSize()
    }
}


#if DEBUG
extension SubscriptionHeroCard {
    static let previewStates: [(title: String, card: SubscriptionHeroCard)] = [
        ("Active — RENEWS (21k)", SubscriptionHeroCard(
            serviceName: "Netflix",
            subtitle: "Monthly · Visa – 4821",
            statusText: "Active", statusTone: .positive,
            amount: "R$ 44,90",
            dateSlot: .renews("Jul 18 · in 5 days"),
            stats: [("This year", "R$ 289,30"), ("Since Nov 23", "R$ 1.312,70")]
        )),
        ("Overdue — EXPECTED · not seen (21m)", SubscriptionHeroCard(
            serviceName: "Globoplay",
            subtitle: "Monthly · Master – 7730",
            statusText: "Overdue", statusTone: .danger,
            amount: "R$ 24,90",
            dateSlot: .expected("Jul 10 · not seen"),
            stats: [("This year", "R$ 149,40"), ("Since Oct 25", "R$ 224,10")]
        )),
        ("Cancelled — PAID THROUGH (21o)", SubscriptionHeroCard(
            serviceName: "Netflix",
            subtitle: "Monthly · Visa – 4821",
            statusText: "Cancelled", statusTone: .danger,
            amount: "R$ 44,90",
            dateSlot: .paidThrough("Aug 18"),
            stats: [("This year", "R$ 289,30"), ("Since Nov 23", "R$ 1.312,70")]
        )),
        ("Ended — PAID THROUGH (21p)", SubscriptionHeroCard(
            serviceName: "Amazon Prime",
            subtitle: "Monthly · Visa – 4821",
            statusText: "Ended", statusTone: .neutral,
            amount: "R$ 19,90",
            dateSlot: .paidThrough("Apr 18"),
            stats: [("This year", "R$ 79,60"), ("Since Jun 24", "R$ 219,90")]
        )),
        ("Widest case — long name + full date slot (#2)", SubscriptionHeroCard(
            serviceName: "EXAMPLE STREAMING CO",
            subtitle: "Monthly · Master – 4321",
            statusText: "Active", statusTone: .positive,
            amount: "R$ 34,51",
            dateSlot: .renews("Aug 19 · in 5 days"),
            stats: [("This year", "R$ 103,53"), ("Since Jun 26", "R$ 103,53")]
        )),
    ]
}

struct HeroStatesGallery: View {
    var indices: [Int] = Array(SubscriptionHeroCard.previewStates.indices)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(indices.filter(SubscriptionHeroCard.previewStates.indices.contains), id: \.self) { index in
                    let state = SubscriptionHeroCard.previewStates[index]
                    VStack(alignment: .leading, spacing: 6) {
                        OverlineText(state.title)
                        state.card
                    }
                }
            }
            .padding(SignuMetric.screenPadding)
        }
        .background(SignuColor.paper)
    }
}

#Preview("Hero · active") { SubscriptionHeroCard.previewStates[0].card.padding(20).background(SignuColor.paper) }
#Preview("Hero · overdue") { SubscriptionHeroCard.previewStates[1].card.padding(20).background(SignuColor.paper) }
#Preview("Hero · cancelled") { SubscriptionHeroCard.previewStates[2].card.padding(20).background(SignuColor.paper) }
#Preview("Hero · ended") { SubscriptionHeroCard.previewStates[3].card.padding(20).background(SignuColor.paper) }
#Preview("All hero states") { HeroStatesGallery() }
#endif
