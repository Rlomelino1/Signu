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

    /// Whole-real rendering for compressed evidence copy: "~R$ 112".
    static func brlWhole(_ amount: Decimal, approximate: Bool = false) -> String {
        var rounded = Decimal()
        var value = amount
        NSDecimalRound(&rounded, &value, 0, .plain)
        let formatted = "R$\u{00A0}\(rounded)"
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
    private static let monthDayShortFormatter = formatter("MMM d")
    private static let weekdayMonthDayFormatter = formatter("EEE, MMM dd")
    private static let weekdayMonthDayYearFormatter = formatter("EEE, MMM dd, yyyy")
    private static let monthYearShortFormatter = formatter("MMM yy")
    private static let monthYearLongFormatter = formatter("MMM yyyy")
    private static let syncStampFormatter = formatter("MMM dd · HH:mm")
    private static let weekdayFullFormatter = formatter("EEEE, MMM d")

    /// "Jul"
    static func monthAbbrev(_ date: Date) -> String { monthAbbrevFormatter.string(from: date) }
    /// "18"
    static func dayNumber(_ date: Date) -> String { dayFormatter.string(from: date) }
    /// "Jul 18"
    static func monthDay(_ date: Date) -> String { monthDayFormatter.string(from: date) }
    /// "Jul 2" — no leading zero, for footer prose (21o/21p).
    static func monthDayShort(_ date: Date) -> String { monthDayShortFormatter.string(from: date) }
    /// "Tue, Apr 15" — timeline rows within the current year.
    static func weekdayMonthDay(_ date: Date) -> String { weekdayMonthDayFormatter.string(from: date) }
    /// "Sat, Nov 18, 2023" — timeline rows in earlier years.
    static func weekdayMonthDayYear(_ date: Date) -> String { weekdayMonthDayYearFormatter.string(from: date) }
    /// "Nov 23" — the hero's SINCE label.
    static func monthYearShort(_ date: Date) -> String { monthYearShortFormatter.string(from: date) }
    /// "Oct 2025" — connection "connected since" line.
    static func monthYearLong(_ date: Date) -> String { monthYearLongFormatter.string(from: date) }
    /// "Jul 12 · 08:14" — connection LAST SYNCED stat.
    static func syncStamp(_ date: Date) -> String { syncStampFormatter.string(from: date) }
    /// "Sunday, Jul 13" — the home header overline (rendered uppercase).
    static func weekdayFull(_ date: Date) -> String { weekdayFullFormatter.string(from: date) }

    /// Timeline row date: "Wed, Jun 18" in the current year, "Sat, Nov 18,
    /// 2023" in earlier years (21k vs 21l).
    static func timelineDate(_ date: Date, referenceYear: Int) -> String {
        let year = MockDataProvider.calendar.component(.year, from: date)
        return year == referenceYear ? weekdayMonthDay(date) : weekdayMonthDayYear(date)
    }

    /// Relative renewal copy: "today" / "tomorrow" / "in 5 days" / "in 3w".
    static func relativeShort(days: Int) -> String {
        switch days {
        case ..<0: "overdue"
        case 0: "today"
        case 1: "tomorrow"
        case 2...14: "in \(days) days"
        default: "in \(Int((Double(days) / 7).rounded()))w"
        }
    }

    /// "just now" / "25m ago" / "2h ago" / "3d ago" — sync-status copy.
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 120 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 172_800 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
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
