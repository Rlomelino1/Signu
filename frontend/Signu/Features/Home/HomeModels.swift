import Foundation

/// Everything the home screen renders, pre-assembled by the data provider
/// (standing in for the future endpoint). The view computes nothing —
/// home screen contract: "UI reads state, never guesses".
struct HomePayload {
    var firstName: String
    var now: Date
    /// Connection-problem banner — the structural severity channel.
    /// Overdue runs never render here (transactional channel: tinted rows).
    var banner: Banner?
    var content: Content

    struct Banner {
        var connectionId: UUID
        var text: String            // "Itaú connection needs attention"
    }

    /// Names the first two and counts the rest: "iFood Clube", "iFood Clube and
    /// MUBI", "iFood Clube, MUBI and 3 more".
    ///
    /// Two is the cutoff because the card has two lines and a third name pushes
    /// the sentence past them at accessibility sizes. The count carries the
    /// remainder rather than the names being truncated, so the number in the
    /// sentence always agrees with the badge beside it.
    static func suggestionNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }

    /// The card's sentence, with the verb agreeing with the count. "looks" for a
    /// lone suggestion reads as written English; "look" for one reads as a bug.
    static func suggestionLine(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let verb = names.count == 1 ? "looks" : "look"
        return "\(suggestionNames(names)) \(verb) recurring — confirm to start tracking."
    }

    enum Content {
        case noBank
        case watching(Watching)
        case active(Active)
    }

    /// Connected, nothing confirmed (21h) — and, when the engine has found
    /// suggestions, the same screen carrying a way to decide on them (22a).
    ///
    /// Before 22a this state said "No subscriptions detected yet" whether or not
    /// anything had been detected, because a `possible` run is a suggestion and
    /// the branch that chooses this state excludes exactly those. A user whose
    /// first sync produced only suggestions was told nothing was found while five
    /// sat in the Subs tab, and Home offered no way to reach the review screen —
    /// which is the only place a suggestion may be confirmed (9a decides).
    struct Watching {
        /// Varies with the two cases this state now covers, because one line
        /// cannot be true of both: "detected" is about what the engine found,
        /// "confirmed" about what the user has decided.
        var headline: String
        var syncText: String
        /// Drives the 22a card and the Subs tab dot. Zero = plain 21h.
        var suggestionCount: Int
        /// "iFood Clube and MUBI look recurring — confirm to start tracking."
        /// nil when there is nothing to review.
        var suggestionLine: String?
    }

    struct Active {
        /// Landed charges this calendar month (primary currency, non-ignored
        /// subscriptions). Pure read of CHARGE — no predictions.
        var monthToDateTotal: Decimal
        var activeCount: Int
        var overdueCount: Int
        /// Like-for-like partial-month delta vs the same day-span of the
        /// previous month; nil when the difference is exactly zero (hidden).
        var deltaVsPreviousMonth: Decimal?
        var previousMonthAbbrev: String
        var syncText: String
        var overdue: [OverdueItem]
        var comingUp: [ComingUpItem]
        /// Non-ignored possible runs — the "Review →" pill count.
        var suggestionCount: Int
        var subscriptions: [SubscriptionItem]
    }

    struct OverdueItem: Identifiable {
        let id: UUID                // run id
        var subscriptionId: UUID
        var serviceName: String
        var expectedDate: Date
        var daysOverdue: Int        // depth into the +10 retry window
        var amount: Decimal
        var approximate: Bool       // detected_by R3 — overdue never downgrades confidence
    }

    struct ComingUpItem: Identifiable {
        let id: UUID                // run id
        var subscriptionId: UUID
        var serviceName: String
        var date: Date
        var daysAway: Int
        var amount: Decimal         // prediction from the last charge
        var approximate: Bool
    }

    struct SubscriptionItem: Identifiable {
        let id: UUID                // subscription id
        var serviceName: String
        var subtitle: String        // "Monthly · Visa 4821"
        var amount: Decimal
        var approximate: Bool
        var nextDate: Date
        var overdueDays: Int?       // non-nil ⇒ render the overdue treatment
    }
}
