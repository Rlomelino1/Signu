import Foundation

/// The renewal calendar (Home's "Coming up · Calendar").
///
/// WHAT IT SHOWS, AND WHAT IT REFUSES TO
///
/// Only `next_expected_date` — the one renewal per run the engine actually
/// stated. It does NOT project further by adding intervals, even though that
/// would fill a month grid nicely, because a projected date is the app inventing
/// a fact the engine declined to assert: cadence can shift, a run can end, and a
/// calendar that quietly renders six months of guesses is exactly the "UI guesses
/// state" failure the doctrine names.
///
/// A month with nothing predicted in it therefore renders empty and says so.
/// That is the honest shape of the data, and the footnote states it on screen
/// rather than leaving the user to infer that Signu forgot their subscriptions.
struct CalendarPayload {
    var monthStart: Date
    /// "August 2026".
    var monthLabel: String
    /// Blank cells before the 1st, so the grid starts on the right weekday.
    var leadingBlanks: Int
    var dayCount: Int
    /// Day-of-month for today, nil when today is in another month.
    var todayDay: Int?
    /// Day-of-month → what renews that day.
    var entriesByDay: [Int: [Entry]]
    /// Σ of everything expected this month, in the primary currency.
    var monthTotal: Decimal
    /// Tilde propagation: true when any R3/R4 run contributes.
    var monthApproximate: Bool

    var isEmpty: Bool { entriesByDay.isEmpty }

    /// Every entry, earliest first — the list under the grid when no day is
    /// selected.
    var allEntries: [Entry] {
        entriesByDay.values.flatMap { $0 }.sorted { $0.date < $1.date }
    }

    struct Entry: Identifiable {
        let id: UUID              // run id
        var subscriptionId: UUID
        var serviceName: String
        var day: Int
        var date: Date
        var amount: Decimal
        var approximate: Bool
        /// The expected date has passed with no charge. Rendered in the overdue
        /// tint, the same as everywhere else — a missed renewal is not a future
        /// one and the calendar must not imply it still lies ahead.
        var overdue: Bool
    }
}
