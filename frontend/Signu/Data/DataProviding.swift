import Foundation

/// Data access boundary. Views never compute doctrine — "UI reads state,
/// never guesses" — so screen-shaped payload methods (home payload, subs-tab
/// payload, detail timeline…) will be added here as each screen lands,
/// mirroring the endpoints the backend will eventually serve. A Supabase
/// provider then slots in behind this protocol without touching views.
///
/// `@MainActor` because every consumer is a SwiftUI view and the live provider
/// caches rows in mutable state that only the main actor may touch. Stating it on
/// the protocol rather than the conformer is what makes that safe: an @MainActor
/// class conforming to a non-isolated protocol warns today and is an **error in
/// the Swift 6 language mode**, because a caller holding the existential could
/// invoke it from anywhere. Isolating the boundary itself removes the hole rather
/// than silencing the diagnostic.
@MainActor
protocol SignuDataProviding {
    /// "Today" as the provider sees it. The mock provider pins this so
    /// previews are deterministic; the live provider returns the real date.
    var today: Date { get }

    func profile() async throws -> Profile
    /// Screen payload for Home — assembled per the home screen contract.
    func homePayload() async throws -> HomePayload
    /// Screen payload for the Subscriptions tab — per the subs tab contract.
    func subsPayload() async throws -> SubsPayload
    /// Screen payload for the Review screen (9a) — possible runs to decide on.
    func reviewPayload() async throws -> ReviewPayload
    /// Screen payload for the subscription detail screen. nil if not found.
    func detailPayload(subscriptionId: UUID) async throws -> DetailPayload?
    /// Settings screen (12a/12d).
    func settingsPayload() async throws -> SettingsPayload
    /// Connection detail (12b). nil if not found.
    func connectionDetailPayload(connectionId: UUID) async throws -> ConnectionDetailPayload?
    /// Attributed-subscriptions list (13a). nil if not found.
    func attributedSubsPayload(connectionId: UUID) async throws -> AttributedSubsPayload?
    /// Delete-account scope counts (14a).
    func deleteAccountScope() async throws -> DeleteAccountScope
    func connections() async throws -> [Connection]
    func bankAccounts() async throws -> [BankAccount]
    func subscriptions() async throws -> [Subscription]
    func runs(subscriptionId: UUID) async throws -> [SubscriptionRun]
    func charges(runId: UUID) async throws -> [Charge]
}
