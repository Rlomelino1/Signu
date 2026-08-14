import Foundation

/// The renewal calendar (Home's "Coming up · Calendar").
///
/// WHAT IT SHOWS, AND WHAT IT REFUSES TO
///
/// **Backwards: every charge that landed.** Those are facts, one row per charge,
/// for every run state — a subscription cancelled in June still cost money in
/// May, and a calendar that hides it reports a cheaper past than the ledger holds
/// (v46).
///
/// **Forwards: only `next_expected_date`** — the one renewal per run the engine
/// actually stated. It does NOT project further by adding intervals, even though
/// that would fill a month grid nicely, because a projected date is the app
/// inventing a fact the engine declined to assert: cadence can shift, a run can
/// end, and a calendar that quietly renders six months of guesses is exactly the
/// "UI guesses state" failure the doctrine names.
///
/// The asymmetry is the point, and it is not a compromise: the past is known and
/// the future is not. A month with nothing in either direction renders empty and
/// says so, and the footnote states the forward limit on screen rather than
/// leaving a thin month to read as lost data.
struct CalendarPayload {
    var monthStart: Date
    /// "August 2026".
    var monthLabel: String
    /// The previous month's trailing days, filling the cells before the 1st.
    ///
    /// Real day numbers rather than empty space, and paired with `trailingDays` so
    /// the grid is **always six rows**. A grid sized to fit each month exactly
    /// changes height as the user pages — the surrounding layout moves under the
    /// thumb, and a 28-day February starting on a Sunday occupies four rows where
    /// a 31-day month starting on a Saturday needs six.
    var leadingDays: [Int]
    /// The next month's leading days, filling the grid out to six rows.
    var trailingDays: [Int]
    var dayCount: Int
    /// Day-of-month for today, nil when today is in another month.
    var todayDay: Int?
    /// Day-of-month → what happened or is expected that day.
    var entriesByDay: [Int: [Entry]]
    /// Σ of the month: what was paid plus what is still expected, in the primary
    /// currency. One figure rather than two, because it answers the question the
    /// screen is for — what the month costs — and it equals the rows beneath it.
    var monthTotal: Decimal
    /// Tilde propagation: true when any R3/R4 run contributes. Only *expected*
    /// entries can, since a landed charge's amount is the transaction's own.
    var monthApproximate: Bool

    var isEmpty: Bool { entriesByDay.isEmpty }

    /// Blank cells before the 1st. Derived, so it cannot disagree with the days
    /// actually rendered there.
    var leadingBlanks: Int { leadingDays.count }

    /// Every entry, earliest first — the list under the grid when no day is
    /// selected.
    var allEntries: [Entry] {
        entriesByDay.values.flatMap { $0 }.sorted { $0.date < $1.date }
    }

    struct Entry: Identifiable {
        /// Charge id for a `paid` entry, run id for the other two. Both are
        /// database identities, so a month holding a run's charge *and* its next
        /// expected date cannot collide.
        let id: UUID
        var subscriptionId: UUID
        var serviceName: String
        var day: Int
        var date: Date
        var amount: Decimal
        var approximate: Bool
        var kind: Kind

        enum Kind {
            /// A charge that landed. A fact, with the transaction's own amount.
            case paid
            /// `next_expected_date`, still ahead.
            case expected
            /// `next_expected_date` has passed with no charge. Rendered in the
            /// overdue tint, the same as everywhere else — a missed renewal is not
            /// a future one and the calendar must not imply it still lies ahead.
            case overdue
        }

        /// Kept as a property so the view and the tests that predate `Kind` read
        /// the same way they did.
        var overdue: Bool { kind == .overdue }
    }
}

extension CalendarPayload.Entry.Kind {
    /// What happened before what is merely expected, within one day.
    var sortRank: Int {
        switch self {
        case .paid: 0
        case .overdue: 1
        case .expected: 2
        }
    }
}
