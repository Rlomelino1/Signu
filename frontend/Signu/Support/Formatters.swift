import Foundation

/// pt-BR currency and mockup date formats, in one place.
/// Tilde rule: `approximate: true` prefixes "~" — one marker, one meaning
/// ("this number is approximate"); markers never stack.
enum SignuFormat {
    private static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.currencyCode = "BRL"
        return formatter
    }()

    /// "R$ 44,90", "R$ 3.405,70"; approximate: "~R$ 283,81".
    static func brl(_ amount: Decimal, approximate: Bool = false) -> String {
        let formatted = currency.string(from: amount as NSDecimalNumber) ?? "R$ \(amount)"
        return approximate ? "~" + formatted : formatted
    }

    /// The empty-money placeholder — the contract's "dash, not R$ 0,00".
    static let dash = "—"

    // Dates render in English per the mockups ("Jul 18", "Tue, Apr 15").
    private static let posixEN = Locale(identifier: "en_US_POSIX")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = posixEN
        formatter.dateFormat = format
        return formatter
    }

    private static let monthAbbrevFormatter = formatter("MMM")
    private static let dayFormatter = formatter("d")
    private static let monthDayFormatter = formatter("MMM dd")
    private static let weekdayMonthDayFormatter = formatter("EEE, MMM d")
    private static let weekdayMonthDayYearFormatter = formatter("EEE, MMM d, yyyy")
    private static let monthYearShortFormatter = formatter("MMM yy")

    /// "Jul"
    static func monthAbbrev(_ date: Date) -> String { monthAbbrevFormatter.string(from: date) }
    /// "18"
    static func dayNumber(_ date: Date) -> String { dayFormatter.string(from: date) }
    /// "Jul 18"
    static func monthDay(_ date: Date) -> String { monthDayFormatter.string(from: date) }
    /// "Tue, Apr 15" — timeline rows within the current year.
    static func weekdayMonthDay(_ date: Date) -> String { weekdayMonthDayFormatter.string(from: date) }
    /// "Sat, Nov 18, 2023" — timeline rows in earlier years.
    static func weekdayMonthDayYear(_ date: Date) -> String { weekdayMonthDayYearFormatter.string(from: date) }
    /// "Nov 23" — the hero's SINCE label.
    static func monthYearShort(_ date: Date) -> String { monthYearShortFormatter.string(from: date) }
}

extension String {
    /// Unbreakable rendering for card labels and similar compounds
    /// ("Monthly · Master – 7730" must never orphan "– 7730"): swaps spaces
    /// for non-breaking spaces and glues the en dash to its neighbors.
    var signuNonBreaking: String {
        replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}")
    }
}
