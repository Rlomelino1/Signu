import Testing
import Foundation
@testable import Signu

// "Updated 3h ago" used to be a claim about our own polling (v65).
//
// `last_synced_at` is written as `new Date()` when a sync FINISHES, so the label
// answered "when did Signu last look" while reading as "how old is this data". The
// two diverge exactly when it matters: Pluggy auto-syncs an item roughly every 24h,
// so on 2026-08-18 the item's data was last refreshed at 15:01Z and our read ran at
// 15:30Z — and on a day when Pluggy's own sync fails, the old label would go on
// saying "Updated 5m ago" about data frozen a day earlier.
//
// A freshness label that cannot express staleness is worse than none: it argues
// against the user's own suspicion that something is behind.

@Suite("Sync freshness (v65)")
@MainActor
struct SyncFreshnessTests {

    private struct StubSource: SignuPayloadSource {
        var today = Date(timeIntervalSince1970: 1_787_000_000)
        var now = Date(timeIntervalSince1970: 1_787_000_000)
        var profileValue: Profile! = Profile(
            id: UUID(), displayName: "Rafael", email: "r@example.test",
            providers: ["email"], avatarPath: nil,
            createdAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
        var connectionList: [Connection] = []
        var accountList: [BankAccount] = []
        var subscriptionList: [Subscription] = []
        var runList: [SubscriptionRun] = []
        var chargeList: [Charge] = []
        var transactionAccountMap: [UUID: UUID] = [:]
    }

    private static func connection(
        synced: Date?, providerUpdated: Date?, status: ConnectionStatus = .active
    ) -> Connection {
        Connection(
            id: UUID(), institutionId: "200", institutionName: "MeuPluggy",
            status: status, consentExpiresAt: nil, lastSyncedAt: synced,
            providerUpdatedAt: providerUpdated, lastSyncError: nil,
            createdAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
    }

    private static let noon = Date(timeIntervalSince1970: 1_787_000_000)
    private static func hoursBefore(_ h: Double) -> Date { noon.addingTimeInterval(-3600 * h) }

    // MARK: - The rule

    @Test("the provider's stamp wins when it is older than our read")
    func providerOlderThanRead() {
        // Production's ordinary shape: Pluggy refreshed at 15:01, we read at 15:30.
        // The data is as of 15:01, and claiming 15:30 overstates it by 29 minutes —
        // small here, unbounded on a day Pluggy's sync fails.
        let c = Self.connection(synced: Self.hoursBefore(1), providerUpdated: Self.hoursBefore(4))
        #expect(c.dataFreshAsOf == Self.hoursBefore(4))
    }

    @Test("our read wins when WE are the stale half")
    func readOlderThanProvider() {
        // The mirror case, and the reason this is a min() rather than "use the
        // provider": if our cron stalled for a day while Pluggy kept refreshing
        // hourly, the provider stamp would describe data we do not have.
        let c = Self.connection(synced: Self.hoursBefore(26), providerUpdated: Self.hoursBefore(2))
        #expect(c.dataFreshAsOf == Self.hoursBefore(26))
    }

    @Test("no provider stamp falls back to our read rather than inventing one")
    func missingProviderStamp() {
        // True of every row until its next sync after Migration #17, and of any
        // provider response that omits the field.
        let c = Self.connection(synced: Self.hoursBefore(3), providerUpdated: nil)
        #expect(c.dataFreshAsOf == Self.hoursBefore(3))
    }

    @Test("a connection that has never synced claims no freshness at all")
    func neverSynced() {
        // "Setting up" (v55) covers this state; a freshness of "now" would be a
        // fabrication, and one of `nil` is what lets the caller choose.
        #expect(Self.connection(synced: nil, providerUpdated: nil).dataFreshAsOf == nil)
        #expect(Self.connection(synced: nil, providerUpdated: Self.hoursBefore(1)).dataFreshAsOf == nil)
    }

    // MARK: - One label for several banks

    @Test("the label speaks for the stalest bank, not the freshest")
    func oldestWins() {
        var source = StubSource()
        source.connectionList = [
            Self.connection(synced: Self.hoursBefore(1), providerUpdated: Self.hoursBefore(2)),
            // A second bank that stopped updating three days ago. Under the old
            // `max()` this was invisible: adding a fresh connection papered over it.
            Self.connection(synced: Self.hoursBefore(70), providerUpdated: Self.hoursBefore(72)),
        ]
        let home = source.makeHomePayload()
        // 72h ≈ 3 days. The exact wording belongs to SignuFormat.ago; what matters
        // here is that the older figure is the one that reaches the screen.
        let text = syncText(home)
        #expect(text.contains("3d") || text.contains("2d"), "\(text)")
        #expect(!text.contains("1h"), "the fresh bank must not speak for the stale one: \(text)")
    }

    @Test("a bank still setting up does not drag the label")
    func settingUpIsNotStaleness() {
        // A connection mid-first-sync has no data on screen yet, so it is not
        // evidence about the data that IS on screen.
        var source = StubSource()
        source.connectionList = [
            Self.connection(synced: Self.hoursBefore(2), providerUpdated: Self.hoursBefore(3)),
            Self.connection(synced: nil, providerUpdated: nil),
        ]
        #expect(syncText(source.makeHomePayload()).contains("3h"))
    }

    private func syncText(_ payload: HomePayload) -> String {
        switch payload.content {
        case .watching(let w): return w.syncText
        case .active(let a): return a.syncText
        case .noBank: return ""
        }
    }
}
