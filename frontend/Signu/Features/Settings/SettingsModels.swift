import Foundation

struct SettingsPayload {
    var displayName: String
    var email: String
    var initial: String
    var avatarPath: String?
    var displayNameIsFallback: Bool
    var providers: [String]
    var hasPassword: Bool
    var banks: [BankRow]
    var dismissed: [DismissedRow]
    var deleteScopeLine: String

    struct BankRow: Identifiable {
        let id: UUID
        var name: String
        var subtitle: String
        var chipText: String
        var chipTone: StatusChip.Tone
    }

    struct DismissedRow: Identifiable {
        let id: UUID
        var name: String
        var subtitle: String
    }
}

struct ConnectionDetailPayload: Identifiable {
    var id: UUID
    var institutionName: String
    var connectedSinceText: String
    var statusText: String
    var statusTone: StatusChip.Tone
    var lastSyncedText: String
    var consentExpiresText: String
    var needsReconnect: Bool
    var reassurance: String
    var cards: [CardRow]
    var summaryCount: Int
    var summaryTotalText: String

    struct CardRow: Identifiable {
        let id: UUID
        var brandMark: String
        var label: String
        var subtitle: String
    }
}

struct AttributedSubsPayload {
    var institutionName: String
    var institutionInitial: String
    var headerCount: Int
    var headerLine: String
    var cardGroups: [CardGroup]
    var dismissed: [Row]

    struct CardGroup: Identifiable {
        let id: UUID
        var header: String
        var rows: [Row]
    }

    struct Row: Identifiable {
        let id: UUID
        var serviceName: String
        var statusLine: String
        var statusTone: StatusChip.Tone
        var amountText: String?
        var unit: String?
    }
}

struct DeleteAccountScope {
    var bankCount: Int
    var subscriptionCount: Int
    var sinceText: String
}
