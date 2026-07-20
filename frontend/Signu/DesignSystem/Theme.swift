import SwiftUI

/// Signu palette, sampled from the locked mockups (21a–21z).
/// Warm off-white paper, ink-dark hero surfaces, muted sage/gold/brick accents.
enum SignuColor {
    // Surfaces
    static let paper = Color(hex: 0xEFEDE6)          // screen background
    static let surface = Color(hex: 0xFAF9F4)        // cards, rows, tab bar
    static let surfaceBright = Color(hex: 0xFDFCF9)  // text fields, focused surfaces
    static let sunken = Color(hex: 0xE7E4DA)         // inset tiles, chips, evidence lists
    static let hairline = Color(hex: 0xE2DFD4)       // separators, outlines

    // Ink (dark hero cards, primary buttons)
    static let ink = Color(hex: 0x2E2924)
    static let inkTile = Color.white.opacity(0.07)   // stat tiles on ink
    static let onInk = Color(hex: 0xF6F4EE)
    static let onInkSecondary = Color(hex: 0xF6F4EE).opacity(0.55)

    // Text
    static let textPrimary = Color(hex: 0x27231C)
    static let textSecondary = Color(hex: 0x807C71)
    static let textTertiary = Color(hex: 0xADA99D)

    // Sage green — suggestions, confirmations, "found" states
    static let green = Color(hex: 0x5B7647)
    static let greenFill = Color(hex: 0x6C8159)
    static let greenTint = Color(hex: 0xDFE4D0)
    static let greenOnInk = Color(hex: 0xA9BF8D)

    // Gold — warnings, price raises, expiring consent
    static let gold = Color(hex: 0x91702A)
    static let goldTint = Color(hex: 0xECE2C6)

    // Brick red — overdue, cancellation, destructive
    static let red = Color(hex: 0xBE4B37)
    static let redFill = Color(hex: 0xC6553F)
    static let redTint = Color(hex: 0xF2DCD5)
    static let redOnInk = Color(hex: 0xE08A78)

    // Tinted alert surfaces (banner / overdue row / suggestion pill),
    // sampled from 21i. Shared rule: tint fill + 1px darker-tint stroke —
    // see View.tintedSurface(fill:stroke:cornerRadius:).
    static let bannerFill = Color(hex: 0xEDE7DC)
    static let bannerStroke = Color(hex: 0xDACAB0)
    static let bannerText = Color(hex: 0x825E16)
    static let overdueRowFill = Color(hex: 0xEFE8E4)
    static let overdueRowStroke = Color(hex: 0xE3C8C1)
    static let overdueBadgeFill = Color(hex: 0xEAD9D4)
    static let greenTintStroke = Color(hex: 0xC9D1C4)
}

/// Spacing and radius tokens.
enum SignuMetric {
    static let screenPadding: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let heroRadius: CGFloat = 28
    static let tileRadius: CGFloat = 16
    static let rowPaddingV: CGFloat = 11
    static let rowPaddingH: CGFloat = 16
    static let buttonHeight: CGFloat = 56
    /// Floating tab bar: 62pt items + 6pt container padding each side.
    static let tabBarHeight: CGFloat = 74
    /// Bottom content inset for scroll views under the floating bar:
    /// bar height + its 8pt lift above the safe area + 12pt breathing room.
    static let scrollBottomInset: CGFloat = tabBarHeight + 8 + 12
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Monogram tile colors (logo contract tier 3). Known services carry the
/// mockups' muted brand hues; unknown merchants fall back deterministically.
enum BrandPalette {
    private static let known: [String: UInt32] = [
        "netflix": 0xB0453C,
        "spotify": 0x55784B,
        "icloud+": 0x8FA6BE,
        "globoplay": 0xB96B35,
        "disney+": 0x5C6E9E,
        "smart fit": 0xC9992E,
        "google one": 0x4E7D8A,
        "duolingo super": 0x57814F,
        "amazon prime": 0x7A74A8,
        "mubi": 0xB394B4,
        "chatgpt plus": 0x5C7D52,
        "chatgpt": 0x5C7D9E,
        "meli+": 0xC79A33,
        "uber one": 0x93A5C0,
        "amazon": 0x94A98D,
        "max": 0x7188B8,
        "prime": 0x6B65A0,
        "nubank": 0x7D5BA6,
        "itaú": 0xBF7434,
        "bradesco": 0xB84A44,
    ]

    private static let fallback: [UInt32] = [
        0xB0453C, 0x55784B, 0x8FA6BE, 0xB96B35,
        0x5C6E9E, 0xC9992E, 0x4E7D8A, 0x7A74A8,
    ]

    static func color(for name: String) -> Color {
        let key = name.lowercased()
        if let hex = known[key] { return Color(hex: hex) }
        let index = abs(key.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % fallback.count
        return Color(hex: fallback[index])
    }
}
