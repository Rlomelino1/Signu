import Foundation

struct ReviewPayload {
    var suggestions: [Suggestion]
    var remindersNeverUsed = true

    struct Suggestion: Identifiable {
        let id: UUID
        var subscriptionId: UUID
        var serviceName: String
        var evidence: String
        var charges: [ChargeLine]
        var renewsDate: Date?
        var renewsAmount: Decimal
        var asksIntervalOnTrack: Bool
        var billingInterval: BillingInterval
    }

    struct ChargeLine: Identifiable {
        let id: UUID
        var dateText: String
        var cardLabel: String
        var amount: Decimal
    }
}
