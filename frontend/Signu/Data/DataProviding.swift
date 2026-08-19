import Foundation

@MainActor
protocol SignuDataProviding {
    var today: Date { get }

    func profile() async throws -> Profile
    func homePayload() async throws -> HomePayload
    func subsPayload() async throws -> SubsPayload
    func reviewPayload() async throws -> ReviewPayload
    func detailPayload(subscriptionId: UUID) async throws -> DetailPayload?
    func settingsPayload() async throws -> SettingsPayload
    func connectionDetailPayload(connectionId: UUID) async throws -> ConnectionDetailPayload?
    func attributedSubsPayload(connectionId: UUID) async throws -> AttributedSubsPayload?
    @discardableResult
    func refresh() async throws -> Bool

    func brandCatalog() async throws -> [BrandCatalogEntry]

    func calendarPayload(monthContaining date: Date) async throws -> CalendarPayload
    func deleteAccountScope() async throws -> DeleteAccountScope
    func connections() async throws -> [Connection]
    func bankAccounts() async throws -> [BankAccount]
    func subscriptions() async throws -> [Subscription]
    func runs(subscriptionId: UUID) async throws -> [SubscriptionRun]
    func charges(runId: UUID) async throws -> [Charge]


    func setReminder(subscriptionId: UUID, remindBeforeDays: Int?) async throws

    func setNickname(subscriptionId: UUID, nickname: String?) async throws

    func setCategory(subscriptionId: UUID, category: String?) async throws

    func setIgnored(subscriptionId: UUID, ignored: Bool) async throws

    func setDisplayName(_ name: String?) async throws

    func setAvatar(jpeg: Data) async throws

    func removeAvatar() async throws

    func avatarData(path: String) async throws -> Data


    func confirmSuggestion(runId: UUID, billingInterval: BillingInterval?) async throws

    func markCancelled(subscriptionId: UUID) async throws

    func removeConnection(connectionId: UUID, deleteHistory: Bool) async throws

    func deleteAccount() async throws


    func connectSession(connectionId: UUID?) async throws -> ConnectSession

    func registerConnection(itemId: String) async throws
}

struct ConnectSession: Equatable {
    let accessToken: String
    var simulated = false
}
