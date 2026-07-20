import SwiftUI

/// Type scale read off the mockups. System font stands in for the mockups'
/// grotesque — no third-party dependencies per the ground rules.
extension Font {
    /// Screen titles: "Subscriptions", "Settings", auth headlines.
    static let signuScreenTitle = Font.system(size: 34, weight: .bold)
    /// Home hero money (R$ 246,40).
    static let signuHeroXL = Font.system(size: 44, weight: .bold)
    /// Subs-tab hero (/yr) and detail-hero money.
    static let signuHero = Font.system(size: 38, weight: .bold)
    /// Greetings, sheet titles ("Remove Itaú?").
    static let signuTitle = Font.system(size: 28, weight: .bold)
    /// In-screen section titles: "Coming up", "History".
    static let signuSection = Font.system(size: 22, weight: .bold)
    /// Detail hero service name, review card titles.
    static let signuHeadline = Font.system(size: 21, weight: .semibold)
    /// Row titles and row amounts.
    static let signuRowTitle = Font.system(size: 17, weight: .semibold)
    static let signuBody = Font.system(size: 17)
    /// Row subtitles, secondary copy.
    static let signuSubtitle = Font.system(size: 15)
    static let signuSubtitleEmphasis = Font.system(size: 15, weight: .semibold)
    static let signuCaption = Font.system(size: 13)
    /// Chips and small controls.
    static let signuChip = Font.system(size: 15, weight: .semibold)
    /// CTA buttons.
    static let signuButton = Font.system(size: 18, weight: .semibold)
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
            .font(.system(size: 13, weight: .semibold))
            .kerning(1.1)
            .foregroundStyle(color)
    }
}
