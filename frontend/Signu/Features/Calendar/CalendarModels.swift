import Foundation

struct CalendarPayload {
    var monthStart: Date
    var monthLabel: String
    var leadingDays: [Int]
    var trailingDays: [Int]
    var dayCount: Int
    var todayDay: Int?
    var entriesByDay: [Int: [Entry]]
    var monthTotal: Decimal
    var monthApproximate: Bool

    var isEmpty: Bool { entriesByDay.isEmpty }

    var leadingBlanks: Int { leadingDays.count }

    var allEntries: [Entry] {
        entriesByDay.values.flatMap { $0 }.sorted { $0.date < $1.date }
    }

    struct Entry: Identifiable {
        let id: UUID
        var subscriptionId: UUID
        var serviceName: String
        var day: Int
        var date: Date
        var amount: Decimal
        var approximate: Bool
        var kind: Kind

        enum Kind {
            case paid
            case expected
            case overdue
        }

        var overdue: Bool { kind == .overdue }
    }
}

extension CalendarPayload.Entry.Kind {
    var sortRank: Int {
        switch self {
        case .paid: 0
        case .overdue: 1
        case .expected: 2
        }
    }
}
