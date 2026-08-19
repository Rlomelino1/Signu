import Testing
import Foundation
@testable import Signu


@Suite("Sync freshness (v65)")
@MainActor
struct SyncFreshnessTests {

    private struct StubSource: SignuPayloadSource {
        var today = Date(timeIntervalSince1970: 1_787_000_000)
        var now = Date(timeIntervalSince1970: 1_787_000_000)
        var profileValue: Profile! = Profile(
            id: UUID(), displayName: "Alex", email: "r@example.test",
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


    @Test("the provider's stamp wins when it is older than our read")
    func providerOlderThanRead() {
        let c = Self.connection(synced: Self.hoursBefore(1), providerUpdated: Self.hoursBefore(4))
        #expect(c.dataFreshAsOf == Self.hoursBefore(4))
    }

    @Test("our read wins when WE are the stale half")
    func readOlderThanProvider() {
        let c = Self.connection(synced: Self.hoursBefore(26), providerUpdated: Self.hoursBefore(2))
        #expect(c.dataFreshAsOf == Self.hoursBefore(26))
    }

    @Test("no provider stamp falls back to our read rather than inventing one")
    func missingProviderStamp() {
        let c = Self.connection(synced: Self.hoursBefore(3), providerUpdated: nil)
        #expect(c.dataFreshAsOf == Self.hoursBefore(3))
    }

    @Test("a connection that has never synced claims no freshness at all")
    func neverSynced() {
        #expect(Self.connection(synced: nil, providerUpdated: nil).dataFreshAsOf == nil)
        #expect(Self.connection(synced: nil, providerUpdated: Self.hoursBefore(1)).dataFreshAsOf == nil)
    }


    @Test("the label speaks for the stalest bank, not the freshest")
    func oldestWins() {
        var source = StubSource()
        source.connectionList = [
            Self.connection(synced: Self.hoursBefore(1), providerUpdated: Self.hoursBefore(2)),
            Self.connection(synced: Self.hoursBefore(70), providerUpdated: Self.hoursBefore(72)),
        ]
        let home = source.makeHomePayload()
        let text = syncText(home)
        #expect(text.contains("3d") || text.contains("2d"), "\(text)")
        #expect(!text.contains("1h"), "the fresh bank must not speak for the stale one: \(text)")
    }

    @Test("a bank still setting up does not drag the label")
    func settingUpIsNotStaleness() {
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
