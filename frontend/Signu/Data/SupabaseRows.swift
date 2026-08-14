import Foundation

// Wire shapes for the interpreted chain, and their mapping to domain models.
//
// Deliberately dumb: one struct per table, field names matching the columns, and
// a `domain` accessor that converts. No filtering, no computation — RLS scopes the
// rows and PayloadSource decides what a screen shows.
//
// TWO DECODING DECISIONS, both taken to avoid trusting a decoder's defaults:
//
// 1. Dates arrive as Strings and are converted here. Postgres `date` columns come
//    back as "2026-06-19" while `timestamptz` comes back ISO8601 with fractional
//    seconds; one JSONDecoder strategy cannot read both, and a misconfigured
//    strategy fails at runtime on a column nobody tested. Explicit is cheaper than
//    debugging that.
//
// 2. Money arrives as Double and is rounded to cents through a string. Postgres
//    `numeric` serialises as a JSON number, and JSON number -> Decimal goes via
//    Double, which can yield 34.510000000000002 and render it. Rounding to cents
//    at the boundary matches the backend, where money is compared as integer cents
//    and never with a float epsilon (v23).

// MARK: - Conversion helpers

private let dateOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = SignuCalendar.saoPaulo
    f.timeZone = SignuCalendar.saoPaulo.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

// `Date.ISO8601FormatStyle`, not `ISO8601DateFormatter`. The format style is a
// Sendable struct; the formatter is a reference type with mutable options that
// Foundation declines to mark Sendable, so a shared global of one is a Swift 6
// error — correctly so. Notably `DateFormatter` above IS annotated Sendable by
// Apple, which is why it stays: they vouched for that one and not for this one,
// and `nonisolated(unsafe)` would be claiming a guarantee nobody gave.
//
// TWO styles, and the fallback is mandatory. `includingFractionalSeconds: true`
// is STRICT on the Foundation shipped with iOS 17 and 18 — it refuses a timestamp
// that has none — and lenient on iOS 26. The deployment target is 17.0, so the
// strict behaviour is what most installed devices do: with one style, every
// `2026-08-10T18:37:13+00:00` would fail to parse in production while passing on
// a current simulator.
//
// Found by CI, whose simulator runs iOS 18.5. A local probe on iOS 26 said
// "lenient in both directions" and that conclusion did not survive the older
// runtime. The tests for both shapes are what caught it.
private let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
private let timestampNoFractionStyle = Date.ISO8601FormatStyle()

extension String {
    /// A `date` column. Noon São Paulo, matching how the mock builds dates, so
    /// day-difference arithmetic in payload assembly cannot straddle a boundary.
    var asPostgresDate: Date? {
        guard let day = dateOnlyFormatter.date(from: self) else { return nil }
        return SignuCalendar.saoPaulo.date(byAdding: .hour, value: 12, to: day)
    }

    /// A `timestamptz` column, with or without fractional seconds.
    ///
    /// Written as two statements, not `try? a ?? b`: in that form `??` binds inside
    /// the `try?` and its left side is non-optional, so the fallback is unreachable.
    /// It compiled, and the test for the no-fraction shape still passed — on a
    /// runtime where the first style accepted both.
    var asPostgresTimestamp: Date? {
        if let withFraction = try? Date(self, strategy: timestampStyle) {
            return withFraction
        }
        return try? Date(self, strategy: timestampNoFractionStyle)
    }
}

extension Double {
    /// Money, rounded to cents. See decoding decision 2 above.
    var asMoney: Decimal {
        Decimal(string: String(format: "%.2f", self)) ?? .zero
    }
}

// MARK: - Rows

struct ProfileRow: Decodable {
    let id: UUID
    let displayName: String?
    let reminderChannels: String
    /// Storage object path, `<uid>/<epoch>.jpg`, or nil for no picture. A path and
    /// never a URL — see Migration #11.
    let avatarPath: String?
    let createdAtRaw: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case reminderChannels = "reminder_channels"
        case avatarPath = "avatar_path"
        case createdAtRaw = "created_at"
    }

    var createdAt: Date { createdAtRaw.asPostgresTimestamp ?? .distantPast }
}

struct ConnectionRow: Decodable {
    let id: UUID
    let institutionId: String
    let institutionName: String
    let status: String
    let consentExpiresAt: String?
    let lastSyncedAt: String?
    let lastSyncError: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case institutionId = "institution_id"
        case institutionName = "institution_name"
        case status
        case consentExpiresAt = "consent_expires_at"
        case lastSyncedAt = "last_synced_at"
        case lastSyncError = "last_sync_error"
        case createdAt = "created_at"
    }

    var domain: Connection {
        Connection(
            id: id,
            institutionId: institutionId,
            institutionName: institutionName,
            // Unknown status is a data problem, not a rendering problem. Falling
            // back to .needsAction rather than .active keeps an unrecognised state
            // from being presented as healthy.
            status: ConnectionStatus(rawValue: status) ?? .needsAction,
            consentExpiresAt: consentExpiresAt?.asPostgresDate,
            lastSyncedAt: lastSyncedAt?.asPostgresTimestamp,
            lastSyncError: lastSyncError,
            createdAt: createdAt.asPostgresTimestamp ?? .distantPast
        )
    }
}

struct BankAccountRow: Decodable {
    let id: UUID
    let connectionId: UUID
    let type: String
    let brand: String?
    let last4: String?
    let officialName: String?
    let nickname: String?
    let status: String
    /// The account's own currency (v26) — the unit for a charge's resolved amount.
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case id
        case connectionId = "connection_id"
        case type, brand, last4
        case officialName = "official_name"
        case nickname, status, currency
    }

    var domain: BankAccount {
        BankAccount(
            id: id,
            connectionId: connectionId,
            type: AccountType(rawValue: type) ?? .checking,
            brand: brand,
            last4: last4 ?? "",
            officialName: officialName ?? "",
            nickname: nickname,
            status: AccountStatus(rawValue: status) ?? .active
        )
    }
}

/// MERCHANT_CATALOG — shared reference data, the same rows for every user, which
/// is why nothing here is scoped by `user_id` and the policy behind it reads
/// `using (true)`.
struct MerchantCatalogRow: Decodable {
    let id: UUID
    let serviceName: String
    let domain: String?
    let category: String?
    let subscriptionOnly: Bool
    let patterns: [String]

    enum CodingKeys: String, CodingKey {
        case id, domain, category, patterns
        case serviceName = "service_name"
        case subscriptionOnly = "subscription_only"
    }

    var domainModel: MerchantCatalogEntry {
        MerchantCatalogEntry(
            id: id,
            serviceName: serviceName,
            domain: domain,
            category: category,
            subscriptionOnly: subscriptionOnly,
            patterns: patterns
        )
    }
}

struct SubscriptionRow: Decodable {
    let id: UUID
    let serviceName: String
    let nickname: String?
    let merchantKey: String
    let category: String?
    let identification: String
    let ignored: Bool
    let remindBeforeDays: Int?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case serviceName = "service_name"
        case nickname
        case merchantKey = "merchant_key"
        case category, identification, ignored
        case remindBeforeDays = "remind_before_days"
        case createdAt = "created_at"
    }

    var domain: Subscription {
        Subscription(
            id: id,
            serviceName: serviceName,
            nickname: nickname,
            merchantKey: merchantKey,
            category: category,
            identification: Identification(rawValue: identification) ?? .auto,
            ignored: ignored,
            remindBeforeDays: remindBeforeDays,
            createdAt: createdAt.asPostgresTimestamp ?? .distantPast
        )
    }
}

struct RunRow: Decodable {
    let id: UUID
    let subscriptionId: UUID
    let startDate: String
    let endDate: String?
    let cancelledDate: String?
    let billingInterval: String
    let status: String
    let detectedBy: String
    let nextExpectedDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case subscriptionId = "subscription_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case cancelledDate = "cancelled_date"
        case billingInterval = "billing_interval"
        case status
        case detectedBy = "detected_by"
        case nextExpectedDate = "next_expected_date"
    }

    var domain: SubscriptionRun {
        SubscriptionRun(
            id: id,
            subscriptionId: subscriptionId,
            startDate: startDate.asPostgresDate ?? .distantPast,
            endDate: endDate?.asPostgresDate,
            cancelledDate: cancelledDate?.asPostgresDate,
            billingInterval: BillingInterval(rawValue: billingInterval) ?? .monthly,
            status: RunStatus(rawValue: status) ?? .active,
            detectedBy: DetectedBy(rawValue: detectedBy) ?? .r1,
            nextExpectedDate: nextExpectedDate?.asPostgresDate
        )
    }
}

struct ChargeRow: Decodable {
    let id: UUID
    let runId: UUID
    let transactionId: UUID?
    let date: String
    let amount: Double
    let currency: String
    let amountInAccountCurrency: Double?
    let cardLabel: String?

    enum CodingKeys: String, CodingKey {
        case id
        case runId = "run_id"
        case transactionId = "transaction_id"
        case date, amount, currency
        case amountInAccountCurrency = "amount_in_account_currency"
        case cardLabel = "card_label"
    }

    /// Resolves to the account's currency. `amount_in_account_currency` is
    /// populated only when the transaction was foreign, and the coalesce is
    /// provably safe: it is null exactly when `currency` already IS the account
    /// currency, verified across all 258 real rows with zero violations (v26).
    ///
    /// `accountCurrency` is passed in because a charge does not know its account —
    /// it reaches one only through `transaction_id`, which is null for charges
    /// whose raw backing was deleted. Those keep their stored currency, which is
    /// the best statement available about them.
    func domain(accountCurrency: String?) -> Charge {
        let isForeign = amountInAccountCurrency != nil
        return Charge(
            id: id,
            runId: runId,
            transactionId: transactionId,
            date: date.asPostgresDate ?? .distantPast,
            amount: (amountInAccountCurrency ?? amount).asMoney,
            currency: isForeign ? (accountCurrency ?? currency) : currency,
            originalAmount: isForeign ? amount.asMoney : nil,
            originalCurrency: isForeign ? currency : nil,
            cardLabel: cardLabel ?? ""
        )
    }
}

struct TransactionRow: Decodable {
    let id: UUID
    let accountId: UUID
    let currency: String?
    let amount: Double?
    let amountInAccountCurrency: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case currency, amount
        case amountInAccountCurrency = "amount_in_account_currency"
    }
}
