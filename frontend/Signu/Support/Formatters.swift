import Foundation

enum SignuFormat {
    private static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.currencyCode = "BRL"
        return formatter
    }()

    static func brl(_ amount: Decimal, approximate: Bool = false) -> String {
        let formatted = currency.string(from: amount as NSDecimalNumber) ?? "R$ \(amount)"
        return approximate ? "~" + formatted : formatted
    }

    static func brlWhole(_ amount: Decimal, approximate: Bool = false) -> String {
        var rounded = Decimal()
        var value = amount
        NSDecimalRound(&rounded, &value, 0, .plain)
        let formatted = "R$\u{00A0}\(rounded)"
        return approximate ? "~" + formatted : formatted
    }

    static let dash = "—"

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
    private static let monthYearFullFormatter = formatter("MMMM yyyy")
    private static let syncStampFormatter = formatter("MMM dd · HH:mm")
    private static let weekdayFullFormatter = formatter("EEEE, MMM d")

    static func monthAbbrev(_ date: Date) -> String { monthAbbrevFormatter.string(from: date) }
    static func dayNumber(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func monthDay(_ date: Date) -> String { monthDayFormatter.string(from: date) }
    static func monthDayShort(_ date: Date) -> String { monthDayShortFormatter.string(from: date) }
    static func weekdayMonthDay(_ date: Date) -> String { weekdayMonthDayFormatter.string(from: date) }
    static func weekdayMonthDayYear(_ date: Date) -> String { weekdayMonthDayYearFormatter.string(from: date) }
    static func monthYearShort(_ date: Date) -> String { monthYearShortFormatter.string(from: date) }
    static func monthYearLong(_ date: Date) -> String { monthYearLongFormatter.string(from: date) }
    static func monthYearFull(_ date: Date) -> String { monthYearFullFormatter.string(from: date) }
    static func syncStamp(_ date: Date) -> String { syncStampFormatter.string(from: date) }
    static func weekdayFull(_ date: Date) -> String { weekdayFullFormatter.string(from: date) }

    static func timelineDate(_ date: Date, referenceYear: Int) -> String {
        let year = SignuCalendar.saoPaulo.component(.year, from: date)
        return year == referenceYear ? weekdayMonthDay(date) : weekdayMonthDayYear(date)
    }

    static func relativeShort(days: Int) -> String {
        switch days {
        case ..<0: "overdue"
        case 0: "today"
        case 1: "tomorrow"
        case 2...14: "in \(days) days"
        default: "in \(Int((Double(days) / 7).rounded()))w"
        }
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 120 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 172_800 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
}

extension String {
    var signuNonBreaking: String {
        replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}")
    }
}
