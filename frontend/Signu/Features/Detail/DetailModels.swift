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
    var showMarkCancelled: Bool
    var footer: String?               // overdue / cancelled / ended honesty copy
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
