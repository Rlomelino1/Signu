import Foundation


enum BillingInterval: String, Codable {
    case monthly
    case annual
}

enum RunLifecycle {
    static let matchWindowDays = 3
    static let overdueGraceDays = 10
    static let deadAfterDays = matchWindowDays + overdueGraceDays
}

enum RunStatus: String, Codable {
    case possible
    case active
    case overdue
    case ended
    case cancelled
}

enum DetectedBy: String, Codable {
    case r1 = "R1"
    case r3 = "R3"
    case r4 = "R4"

    var isApproximate: Bool { self == .r3 || self == .r4 }
}

enum ConnectionStatus: String, Codable {
    case active
    case needsAction = "needs_action"
    case expired
    case disconnected
}

enum AccountType: String, Codable {
    case creditCard = "credit_card"
    case checking
}

enum AccountStatus: String, Codable {
    case active
    case closed
}

enum Identification: String, Codable {
    case auto
    case userConfirmed = "user_confirmed"
    case userRenamed = "user_renamed"
}

enum ReminderChannels: String, Codable {
    case push
    case email
    case both
}

struct Profile: Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var displayNameIsFallback: Bool = false
    var email: String
    var providers: [String]
    var reminderChannels: ReminderChannels = .email
    var avatarPath: String?
    var createdAt: Date
}

struct Connection: Identifiable, Hashable {
    let id: UUID
    var institutionId: String
    var institutionName: String
    var status: ConnectionStatus
    var consentExpiresAt: Date?
    var lastSyncedAt: Date?
    var providerUpdatedAt: Date? = nil
    var lastSyncError: String?
    var createdAt: Date

    var dataFreshAsOf: Date? {
        guard let synced = lastSyncedAt else { return nil }
        guard let provider = providerUpdatedAt else { return synced }
        return min(provider, synced)
    }
}

struct BankAccount: Identifiable, Hashable {
    let id: UUID
    var connectionId: UUID
    var type: AccountType
    var brand: String?
    var last4: String
    var officialName: String
    var nickname: String?
    var status: AccountStatus
}

struct Subscription: Identifiable, Hashable {
    let id: UUID
    var serviceName: String
    var nickname: String?
    var merchantKey: String
    var category: String?
    var identification: Identification = .auto
    var ignored = false
    var remindBeforeDays: Int?
    var createdAt: Date

    var displayName: String { nickname ?? serviceName }
}

struct SubscriptionRun: Identifiable, Hashable {
    let id: UUID
    var subscriptionId: UUID
    var startDate: Date
    var endDate: Date?
    var cancelledDate: Date?
    var billingInterval: BillingInterval
    var status: RunStatus
    var detectedBy: DetectedBy
    var nextExpectedDate: Date?
}

struct Charge: Identifiable, Hashable {
    let id: UUID
    var runId: UUID
    var transactionId: UUID?
    var date: Date
    var amount: Decimal
    var currency: String
    var originalAmount: Decimal? = nil
    var originalCurrency: String? = nil
    var cardLabel: String

    var isForeignCurrency: Bool { originalAmount != nil }
}
