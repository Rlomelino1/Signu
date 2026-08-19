import Foundation

struct SubsPayload {
    var yearlyTotal: Decimal
    var yearlyApproximate: Bool
    var monthlyCompanion: Decimal

    var allCount: Int
    var activeCount: Int
    var inactiveCount: Int

    var suggested: [SuggestedItem]
    var monthly: Group
    var annual: Group
    var inactive: [InactiveItem]

    struct Group {
        var subtotal: Decimal
        var approximate: Bool
        var unitSuffix: String
        var rows: [Row]
    }

    struct Row: Identifiable {
        let id: UUID
        var serviceName: String
        var subtitle: String
        var amount: Decimal
        var approximate: Bool
        var nextDate: Date
        var overdueDays: Int?
        var share: Double
    }

    struct SuggestedItem: Identifiable {
        let id: UUID
        var subscriptionId: UUID
        var serviceName: String
        var evidence: String
    }

    struct InactiveItem: Identifiable {
        let id: UUID
        var serviceName: String
        var statusText: String
        var paidThroughText: String
        var cancelled: Bool
    }
}
