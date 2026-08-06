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

    enum Content {
        case noBank
        case watching(syncText: String)
        case active(Active)
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
