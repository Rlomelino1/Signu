import Foundation



private let dateOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = SignuCalendar.saoPaulo
    f.timeZone = SignuCalendar.saoPaulo.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
private let timestampNoFractionStyle = Date.ISO8601FormatStyle()

extension String {
    var asPostgresDate: Date? {
        guard let day = dateOnlyFormatter.date(from: self) else { return nil }
        return SignuCalendar.saoPaulo.date(byAdding: .hour, value: 12, to: day)
    }

    var asPostgresTimestamp: Date? {
        if let withFraction = try? Date(self, strategy: timestampStyle) {
            return withFraction
        }
        return try? Date(self, strategy: timestampNoFractionStyle)
    }
}

extension Double {
    var asMoney: Decimal {
        Decimal(string: String(format: "%.2f", self)) ?? .zero
    }
}


struct ProfileRow: Decodable {
    let id: UUID
    let displayName: String?
    let reminderChannels: String
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
    let providerUpdatedAt: String?
    let lastSyncError: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case institutionId = "institution_id"
        case institutionName = "institution_name"
        case status
        case consentExpiresAt = "consent_expires_at"
        case lastSyncedAt = "last_synced_at"
        case providerUpdatedAt = "provider_updated_at"
        case lastSyncError = "last_sync_error"
        case createdAt = "created_at"
    }

    var domain: Connection {
        Connection(
            id: id,
            institutionId: institutionId,
            institutionName: institutionName,
            status: ConnectionStatus(rawValue: status) ?? .needsAction,
            consentExpiresAt: consentExpiresAt?.asPostgresDate,
            lastSyncedAt: lastSyncedAt?.asPostgresTimestamp,
            providerUpdatedAt: providerUpdatedAt?.asPostgresTimestamp,
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

struct BrandCatalogRow: Decodable {
    let id: UUID
    let brandName: String
    let domain: String?
    let category: String?
    let subscriptionOnly: Bool
    let kind: String
    let patterns: [String]

    enum CodingKeys: String, CodingKey {
        case id, domain, category, patterns
        case brandName = "brand_name"
        case subscriptionOnly = "subscription_only"
        case kind
    }

    var domainModel: BrandCatalogEntry {
        BrandCatalogEntry(
            id: id,
            brandName: brandName,
            domain: domain,
            category: category,
            subscriptionOnly: subscriptionOnly,
            kind: BrandKind(rawValue: kind) ?? .service,
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
