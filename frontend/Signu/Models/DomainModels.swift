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
    /// True when `displayName` is standing in for a name the user never gave, so
    /// screens can decline to greet someone by their email address. The fallback
    /// itself stays in place — a blank greeting would be worse — but "Hi
    /// you@example.com" is not a greeting either.
    var displayNameIsFallback: Bool = false
    var email: String
    var providers: [String]          // from auth.users identities: "google", "email"
    var reminderChannels: ReminderChannels = .email
    /// Storage object path of the profile picture, or nil for the monogram.
    var avatarPath: String?
    var createdAt: Date
}

struct Connection: Identifiable, Hashable {
    let id: UUID
    var institutionId: String
    var institutionName: String
    var status: ConnectionStatus
    var consentExpiresAt: Date?
    /// When **we** last finished reading Pluggy. Answers "is Signu's polling
    /// working", which is not the same question as "how old is this data".
    var lastSyncedAt: Date?
    /// When **Pluggy** last refreshed this item from the institution — its own
    /// `item.lastUpdatedAt` (v65). Nil on connections not synced since Migration
    /// #17, and nil whenever the provider omits it.
    var providerUpdatedAt: Date? = nil
    var lastSyncError: String?
    var createdAt: Date

    /// The oldest moment this connection's data can honestly be claimed to reflect.
    ///
    /// Bounded by BOTH hops, so it is the earlier of the two: our copy shows the
    /// provider's state as of our last read, and the provider's state is itself as
    /// old as its last refresh. Taking the later of them is how "Updated 5m ago"
    /// ended up describing data that Pluggy had frozen a day earlier.
    ///
    /// Nil when no sync has ever completed — there is no freshness to claim, and the
    /// "Setting up" copy (v55) covers that state instead.
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
    /// **Always in the account's currency**, so totals sum and `SignuFormat.brl`
    /// is right. Postgres stores two amounts — the transaction amount in
    /// `charge.amount` and the account-currency value in
    /// `charge.amount_in_account_currency`, populated only when the transaction
    /// was foreign (v26). The provider coalesces them here, at the boundary,
    /// rather than at the dozen sites that read this.
    ///
    /// Without that, a USD Steam charge renders as R$6.45 instead of R$34.51 —
    /// wrong by 5.3x — because the formatter hardcodes BRL.
    var amount: Decimal
    /// The **account's** currency, not necessarily the transaction's.
    var currency: String
    /// What the merchant actually charged, when that differs from `amount`. nil
    /// for a domestic charge. Nothing renders it yet; carried so the detail screen
    /// can show "$6.45 USD" later without a migration or a provider change.
    var originalAmount: Decimal? = nil
    var originalCurrency: String? = nil
    var cardLabel: String            // snapshot at billing time, e.g. "Visa 4821"

    /// True when the merchant billed in another currency, so the displayed BRL
    /// figure is a conversion that moves between cycles.
    var isForeignCurrency: Bool { originalAmount != nil }
}
