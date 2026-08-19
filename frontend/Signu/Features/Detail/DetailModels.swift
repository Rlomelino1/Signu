import Foundation

struct DetailPayload: Identifiable {
    var id: UUID
    var serviceName: String
    var subtitle: String
    var statusText: String
    var statusTone: StatusChip.Tone
    var amountText: String
    var unit: String
    var dateSlot: SubscriptionHeroCard.DateSlot
    var thisYearText: String
    var sinceLabel: String
    var sinceTotalText: String

    var events: [TimelineEvent]

    var showRemindMe: Bool
    var reminderOn: Bool
    var showMarkCancelled: Bool
    var footer: String?

    var nickname: String?
    var engineName: String
    var category: String?
    var knownCategories: [String]
}

struct TimelineEvent: Identifiable {
    let id: UUID
    var title: String
    var dateText: String
    var amountText: String?
    var tone: Tone
    var marker: Marker
    var uppercaseTitle: Bool = false
    var lineAbove: Line = .solid
    var lineBelow: Line = .solid

    enum Tone { case normal, positive, warning, danger, info, muted }
    enum Marker { case filled, ring }
    enum Line { case none, solid, dashed }
}
