import Foundation

/// Settings screen (12a / 12d empty state).
struct SettingsPayload {
    var displayName: String
    var email: String
    var initial: String
    var providers: [String]              // "Google" / "Password"
    /// Drives the v19 password row off the same identities the chips render:
    /// present ⇒ "Change password", Google-only ⇒ "Set a password". Data, so it
    /// lives here; the two copy strings are static and live in the view.
    var hasPassword: Bool
    var banks: [BankRow]
    var dismissed: [DismissedRow]
    var deleteScopeLine: String          // "Everything, permanently — banks, history, profile"

    struct BankRow: Identifiable {
        let id: UUID                     // connection id
        var name: String
        var subtitle: String
        var chipText: String
        var chipTone: StatusChip.Tone
    }

    struct DismissedRow: Identifiable {
        let id: UUID                     // subscription id
        var name: String
        var subtitle: String             // "Not a subscription · Jun 14"
    }
}

/// Connection detail (12b).
struct ConnectionDetailPayload: Identifiable {
    var id: UUID                         // connection id
    var institutionName: String
    var connectedSinceText: String       // "Connected Oct 2025 · via Open Finance"
    var statusText: String
    var statusTone: StatusChip.Tone
    var lastSyncedText: String           // "Jul 12 · 08:14"
    var consentExpiresText: String       // "Sep 28"
    var needsReconnect: Bool
    var reassurance: String
    var cards: [CardRow]
    var summaryCount: Int                // "N subscriptions found via this bank"
    var summaryTotalText: String         // "R$ 1.412,80 tracked since Oct 25"

    struct CardRow: Identifiable {
        let id: UUID                     // account id
        var brandMark: String            // "VISA" / "MC" / "ELO"
        var label: String                // "Visa – 4821"
        var subtitle: String             // "4 subscriptions billed here"
    }
}

/// Attributed-subscriptions list (13a).
struct AttributedSubsPayload {
    var institutionName: String
    var institutionInitial: String
    var headerCount: Int
    var headerLine: String               // "7 subscriptions · R$ 1.412,80 since Oct 25"
    var cardGroups: [CardGroup]
    var dismissed: [Row]

    struct CardGroup: Identifiable {
        let id: UUID                     // account id
        var header: String               // "VISA ···· 4821 · 4"
        var rows: [Row]
    }

    struct Row: Identifiable {
        let id: UUID                     // subscription id
        var serviceName: String
        var statusLine: String           // "Renews Jul 22" / "Overdue · expected Jul 10" / "Ended · paid through Mar 12" / "Not a subscription · Jun 14"
        var statusTone: StatusChip.Tone  // danger for overdue, else normal
        var amountText: String?          // nil for dismissed rows
        var unit: String?                // "/mo" | "/yr"
    }
}

/// Delete-account sheet (14a).
struct DeleteAccountScope {
    var bankCount: Int
    var subscriptionCount: Int           // includes ignored
    var sinceText: String
}
