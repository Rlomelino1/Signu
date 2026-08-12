import Foundation

/// Everything the subscription detail screen renders (4b/5a–5d/10a/11a —
/// mockups 21k–21q). The timeline is pre-assembled and interleaved by the
/// provider (endpoint-synthesis note); the view computes nothing.
struct DetailPayload: Identifiable {
    var id: UUID                      // subscription id
    var serviceName: String
    var subtitle: String              // "Monthly · Visa – 4821"
    var statusText: String
    var statusTone: StatusChip.Tone
    var amountText: String            // hero money, pre-formatted (tilde iff R3/R4)
    var unit: String                  // "/mo" | "/yr"
    var dateSlot: SubscriptionHeroCard.DateSlot
    var thisYearText: String
    var sinceLabel: String            // "Since Nov 23" | "Since Sep 25 · 2 runs"
    var sinceTotalText: String

    var events: [TimelineEvent]

    /// Bottom action bar / footer, by state.
    var showRemindMe: Bool
    /// Whether a reminder is already set — `subscription.remind_before_days != nil`.
    /// Distinct from `showRemindMe`, which only says whether the button appears at
    /// all. Without this the toggle always rendered "Remind me" regardless of the
    /// stored value, so the first tap on an already-on reminder turned it OFF while
    /// the label claimed it had turned on. Harmless while nothing persisted; a
    /// defect the moment it did.
    var reminderOn: Bool
    var showMarkCancelled: Bool
    var footer: String?               // overdue / cancelled / ended honesty copy

    /// The user's own name, when they have set one. Distinct from `serviceName`,
    /// which is already `nickname ?? service_name` — the rename sheet needs to
    /// know which of the two it is looking at, because clearing the nickname is a
    /// real action and "no nickname" must not render as "delete my own name".
    var nickname: String?
    /// The engine's own name for the merchant, unaffected by a nickname. The
    /// rename sheet needs it for its placeholder and its "use X again" action:
    /// `serviceName` above is already the display name, so it would show the
    /// nickname back to the user as though it were the original.
    var engineName: String
    var category: String?
    /// Categories already present in this user's data. The engine seeds them, so
    /// the client offers what exists rather than asserting a taxonomy of its own.
    var knownCategories: [String]
}

/// A single self-narrating timeline row. Marker semantics (locked with
/// Rafael, System B): filled = happened/landed; ring = hasn't happened
/// (upcoming renewal, expected/missed charge, not-subscribed gap).
struct TimelineEvent: Identifiable {
    let id: UUID
    var title: String
    var dateText: String
    var amountText: String?           // nil for events without an amount
    var tone: Tone
    var marker: Marker
    var uppercaseTitle: Bool = false  // NOT SUBSCRIBED gap
    var lineAbove: Line = .solid
    var lineBelow: Line = .solid

    enum Tone { case normal, positive, warning, danger, info, muted }
    enum Marker { case filled, ring }
    enum Line { case none, solid, dashed }
}
