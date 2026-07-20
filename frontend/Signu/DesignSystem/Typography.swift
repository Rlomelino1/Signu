import SwiftUI

/// App typeface: Inter (bundled, SIL OFL — see Fonts/OFL-Inter-LICENSE.txt),
/// registered via UIAppFonts. Every text style in the app routes through
/// here; no view uses the system font directly.
enum SignuFont {
    enum Weight {
        case regular, medium, semibold, bold

        var faceName: String {
            switch self {
            case .regular: "Inter-Regular"
            case .medium: "Inter-Medium"
            case .semibold: "Inter-SemiBold"
            case .bold: "Inter-Bold"
            }
        }
    }

    /// `tabular` turns on monospaced (tabular) numerals — required on any
    /// style that renders amounts, so digits align down lists and tiles.
    static func font(_ size: CGFloat, _ weight: Weight = .regular, tabular: Bool = false) -> Font {
        let font = Font.custom(weight.faceName, size: size)
        return tabular ? font.monospacedDigit() : font
    }
}

/// Type scale read off the mockups.
extension Font {
    /// Screen titles: "Subscriptions", "Settings", auth headlines.
    static let signuScreenTitle = SignuFont.font(34, .bold)
    /// Hero money on uncontested rows (home + subs-tab heroes).
    static let signuHeroXL = SignuFont.font(44, .bold, tabular: true)
    /// Detail-hero money: shares its row with the date slot, so it is
    /// capped at the measured no-truncation size (see FontDiagnostics;
    /// Inter@44 is ~223pt against a ~148pt budget on 393pt screens).
    static let signuHeroDetail = SignuFont.font(32, .bold, tabular: true)
    /// Secondary hero money slot.
    static let signuHero = SignuFont.font(38, .bold, tabular: true)
    /// Greetings, sheet titles ("Remove Itaú?").
    static let signuTitle = SignuFont.font(28, .bold)
    /// In-screen section titles: "Coming up", "History".
    static let signuSection = SignuFont.font(22, .bold)
    /// Detail hero service name, review card titles.
    static let signuHeadline = SignuFont.font(21, .semibold)
    /// Row titles and row amounts.
    static let signuRowTitle = SignuFont.font(17, .semibold, tabular: true)
    static let signuBody = SignuFont.font(17)
    /// Row subtitles, secondary copy.
    static let signuSubtitle = SignuFont.font(15)
    static let signuSubtitleEmphasis = SignuFont.font(15, .semibold, tabular: true)
    static let signuCaption = SignuFont.font(13)
    /// Chips and small controls.
    static let signuChip = SignuFont.font(14, .semibold)
    /// CTA buttons.
    static let signuButton = SignuFont.font(18, .semibold)
    /// Stat-tile values (ink hero tiles). 17pt keeps "R$ 1.312,70" on one
    /// line inside a half-width tile on 393pt screens.
    static let signuStatValue = SignuFont.font(17, .semibold, tabular: true)
}

/// Uppercase, letterspaced label — section headers, hero stat labels.
struct OverlineText: View {
    let text: String
    var color: Color = SignuColor.textSecondary

    init(_ text: String, color: Color = SignuColor.textSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(SignuFont.font(13, .semibold, tabular: true))
            .kerning(1.1)
            .foregroundStyle(color)
    }
}
