import Foundation

/// Data access boundary. Views never compute doctrine — "UI reads state,
/// never guesses" — so screen-shaped payload methods (home payload, subs-tab
/// payload, detail timeline…) will be added here as each screen lands,
/// mirroring the endpoints the backend will eventually serve. A Supabase
/// provider then slots in behind this protocol without touching views.
protocol SignuDataProviding {
    /// "Today" as the provider sees it. The mock provider pins this so
    /// previews are deterministic; the live provider returns the real date.
    var today: Date { get }

    func profile() async throws -> Profile
    func connections() async throws -> [Connection]
    func bankAccounts() async throws -> [BankAccount]
    func subscriptions() async throws -> [Subscription]
    func runs(subscriptionId: UUID) async throws -> [SubscriptionRun]
    func charges(runId: UUID) async throws -> [Charge]
}
