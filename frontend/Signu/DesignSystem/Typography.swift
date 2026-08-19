import SwiftUI

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

    static func font(_ size: CGFloat, _ weight: Weight = .regular, tabular: Bool = false) -> Font {
        let font = Font.custom(weight.faceName, size: size)
        return tabular ? font.monospacedDigit() : font
    }
}

extension Font {
    static let signuScreenTitle = SignuFont.font(34, .bold)
    static let signuHeroXL = SignuFont.font(44, .bold, tabular: true)
    static let signuHeroCompact = SignuFont.font(32, .bold, tabular: true)
    static let signuHero = SignuFont.font(38, .bold, tabular: true)
    static let signuTitle = SignuFont.font(28, .bold)
    static let signuSection = SignuFont.font(22, .bold)
    static let signuHeadline = SignuFont.font(21, .semibold)
    static let signuRowTitle = SignuFont.font(17, .semibold, tabular: true)
    static let signuBody = SignuFont.font(17)
    static let signuSubtitle = SignuFont.font(15)
    static let signuSubtitleEmphasis = SignuFont.font(15, .semibold, tabular: true)
    static let signuCaption = SignuFont.font(13)
    static let signuChip = SignuFont.font(14, .semibold)
    static let signuButton = SignuFont.font(18, .semibold)
    static let signuStatValue = SignuFont.font(17, .semibold, tabular: true)
}

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
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
