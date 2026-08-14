import SwiftUI

/// The subscription detail hero (4b/10a/11a): ink card with service identity,
/// contract-price amount, the uniform date slot, and lifetime stat tiles.
///
/// Date slot rule (locked): one slot, one date column, three labels by state —
/// RENEWS (active), EXPECTED + "not seen" (overdue), PAID THROUGH (cancelled
/// and ended). Never "last charge".
///
/// Tilde stays `detected_by`-only: overdue never downgrades amount confidence,
/// so callers pass exact amounts for R1 runs regardless of run state.
struct SubscriptionHeroCard: View {
    enum DateSlot {
        case renews(String)         // "Jul 18 · in 5 days"
        case expected(String)       // "Jul 10 · not seen"
        case paidThrough(String)    // "Aug 18"

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

        /// Dead runs (both cancelled and ended) show PAID THROUGH; the
        /// mockups render their amount slightly muted.
        var isDead: Bool {
            if case .paidThrough = self { return true }
            return false
        }
    }

    let serviceName: String
    let subtitle: String            // "Monthly · Visa – 4821"
    let statusText: String
    let statusTone: StatusChip.Tone
    let amount: String              // pre-formatted, tilde included when R3
    var unit: String? = "/mo"
    let dateSlot: DateSlot
    let stats: [(label: String, value: String)]

    var body: some View {
        InkHeroCard {
            // Chip centers against the name + subtitle block as a whole (21o).
            HStack(alignment: .center, spacing: 12) {
                ServiceAvatar(name: serviceName, size: 46)
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

    /// Amount beside the date slot, or above it when they cannot both fit.
    ///
    /// **A cropped number is a wrong number.** "R$ 34,…" is not an amount, and
    /// unlike a truncated service name the user cannot rename their way out of it.
    /// The side-by-side row is the design (21k: the amount dominates and the date
    /// slot's bottom line shares its baseline) and it is tried first — but it is
    /// only honest while both halves fit.
    ///
    /// `ViewThatFits` rather than a Dynamic Type threshold, because the overflow
    /// is not caused by type size alone: a long amount, a long date slot
    /// ("Aug 19 · in 5 days" is the widest the slot produces) and a large text
    /// size each contribute, and measuring the result is exact where a hardcoded
    /// breakpoint is a guess. It works here because the row's ideal width is
    /// honest — `Spacer(minLength: 8)` reports 8, and the date block is
    /// `.fixedSize()`.
    ///
    /// The stacked fallback moves the date under the amount, both at full size
    /// and both left-aligned. Losing the shared baseline is the cost; losing
    /// digits was never an option.
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
                // Second line of defence, for the case even the stacked layout
                // cannot fit at full size. Every other number in the ink hero
                // already scales — both `HeroStatTile` lines do (0.7 and 0.6) —
                // and this was the one site that missed the convention while
                // being the largest number on the screen.
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

// MARK: - The four run states, with the mockups' data (21k/21m/21o/21p)

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
        // The production row that found the crop, verbatim: a long merchant name
        // from the real ledger, the widest date slot the layout produces
        // ("· in 5 days" on top of a date), and an amount long enough that the
        // three together overflowed. The state is kept as a preview rather than a
        // test because the failure is geometric — it can only be seen, and a
        // screenshot of this is what closed #2.
        ("Widest case — long name + full date slot (#2)", SubscriptionHeroCard(
            serviceName: "TRUELINE VALVE CORPORATION",
            subtitle: "Monthly · Master – 2049",
            statusText: "Active", statusTone: .positive,
            amount: "R$ 34,51",
            dateSlot: .renews("Aug 19 · in 5 days"),
            stats: [("This year", "R$ 103,53"), ("Since Jun 26", "R$ 103,53")]
        )),
    ]
}

/// Debug harness: hero states in one scroll. Reachable in the simulator via
/// launch argument `--hero-states` (all) or `--hero-states=0,1` (subset).
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
