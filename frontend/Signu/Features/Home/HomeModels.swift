import Foundation

struct HomePayload {
    var firstName: String?
    var initial: String
    var avatarPath: String?
    var now: Date
    var banner: Banner?
    var content: Content

    struct Banner {
        var connectionId: UUID
        var text: String
    }

    static func suggestionNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }

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

    struct Watching {
        var headline: String
        var syncText: String
        var suggestionCount: Int
        var suggestionLine: String?
    }

    struct Active {
        var monthToDateTotal: Decimal
        var activeCount: Int
        var overdueCount: Int
        var deltaVsPreviousMonth: Decimal?
        var previousMonthAbbrev: String
        var syncText: String
        var overdue: [OverdueItem]
        var comingUp: [ComingUpItem]
        var suggestionCount: Int
        var subscriptions: [SubscriptionItem]
    }

    struct OverdueItem: Identifiable {
        let id: UUID
        var subscriptionId: UUID
        var serviceName: String
        var expectedDate: Date
        var daysOverdue: Int
        var amount: Decimal
        var approximate: Bool
    }

    struct ComingUpItem: Identifiable {
        let id: UUID
        var subscriptionId: UUID
        var serviceName: String
        var date: Date
        var daysAway: Int
        var amount: Decimal
        var approximate: Bool
    }

    struct SubscriptionItem: Identifiable {
        let id: UUID
        var serviceName: String
        var subtitle: String
        var amount: Decimal
        var approximate: Bool
        var nextDate: Date
        var overdueDays: Int?
    }
}
