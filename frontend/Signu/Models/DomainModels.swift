import Foundation

// Domain models mirroring the Supabase schema (data model v12).
// Raw-chain tables (TRANSACTION) are omitted for now — the UI never reads
// them directly; charges are self-contained by design.

enum BillingInterval: String, Codable {
    case monthly
    case annual
}

enum RunStatus: String, Codable {
    case possible
    case active
    case overdue
    case ended
    case cancelled
}

/// Powers expected-exact vs expected-approximate. R1 ⇒ exact; R3 ⇒ approximate
/// (tilde); R4 runs are possible-only until confirmed. R2 is backfill and
/// never appears here.
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
    var email: String
    var providers: [String]          // from auth.users identities: "google", "email"
    var reminderChannels: ReminderChannels = .email
    var createdAt: Date
}

struct Connection: Identifiable, Hashable {
    let id: UUID
    var institutionId: String
    var institutionName: String
    var status: ConnectionStatus
    var consentExpiresAt: Date?
    var lastSyncedAt: Date?
    var lastSyncError: String?
    var createdAt: Date
}

struct BankAccount: Identifiable, Hashable {
    let id: UUID
    var connectionId: UUID
    var type: AccountType
    var brand: String?               // Visa / Mastercard / Elo…; nil for non-cards
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
    var createdAt: Date              // first detected = "tracking since"

    var displayName: String { nickname ?? serviceName }
}

struct SubscriptionRun: Identifiable, Hashable {
    let id: UUID
    var subscriptionId: UUID
    var startDate: Date
    var endDate: Date?               // nil = active; else paid-through
    var cancelledDate: Date?         // user-asserted cancellation, nil otherwise
    var billingInterval: BillingInterval
    var status: RunStatus
    var detectedBy: DetectedBy
    var nextExpectedDate: Date?      // always nil on cancelled runs
}

struct Charge: Identifiable, Hashable {
    let id: UUID
    var runId: UUID
    var transactionId: UUID?         // nil once raw data is deleted
    var date: Date
    var amount: Decimal
    var currency: String
    var cardLabel: String            // snapshot at billing time, e.g. "Visa 4821"
}
