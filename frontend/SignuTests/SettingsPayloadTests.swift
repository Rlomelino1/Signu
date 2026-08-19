import Testing
import Foundation
@testable import Signu


private struct StubSource: SignuPayloadSource {
    var providers: [String]

    var today = Date(timeIntervalSince1970: 1_780_000_000)
    var now = Date(timeIntervalSince1970: 1_780_000_000)
    var profileValue: Profile! {
        Profile(
            id: UUID(),
            displayName: "Alex Rivera",
            email: "rafael.souza@example.com",
            providers: providers,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
    }
    var connectionList: [Connection] = []
    var accountList: [BankAccount] = []
    var subscriptionList: [Subscription] = []
    var runList: [SubscriptionRun] = []
    var chargeList: [Charge] = []
    var transactionAccountMap: [UUID: UUID] = [:]
}

@Suite("Settings profile rows (v19)")
@MainActor
struct SettingsPayloadTests {

    @Test("a password identity means the row offers to change one")
    func bothIdentities() {
        let payload = StubSource(providers: ["google", "email"]).makeSettingsPayload()
        #expect(payload.hasPassword)
        #expect(payload.providers == ["Google", "Password"])
    }

    @Test("Google-only means the row offers to set one")
    func googleOnly() {
        let payload = StubSource(providers: ["google"]).makeSettingsPayload()
        #expect(!payload.hasPassword)
        #expect(payload.providers == ["Google"])
    }

    @Test("the derivation reads the raw identity, not the chip label")
    func notTheLabel() {
        let payload = StubSource(providers: ["email"]).makeSettingsPayload()
        #expect(payload.hasPassword)
        #expect(payload.providers == ["Password"])
        #expect(!payload.providers.contains("email"))
    }

    @Test("an identity provider nobody has mapped yet still renders")
    func unknownProvider() {
        let payload = StubSource(providers: ["apple"]).makeSettingsPayload()
        #expect(payload.providers == ["Apple"])
        #expect(!payload.hasPassword)
    }

    @Test("one cooldown constant, so the three surfaces cannot drift")
    func oneCooldown() {
        #expect(AuthCooldown.seconds >= 60)
    }

    @Test("the cooldown is computed from elapsed time, not counted down")
    func cooldownRemaining() {
        let sent = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(AuthCooldown.remaining(since: nil, now: sent) == 0)
        #expect(AuthCooldown.remaining(since: sent, now: sent) == AuthCooldown.seconds)
        #expect(AuthCooldown.remaining(since: sent, now: sent.addingTimeInterval(60)) == 60)
        #expect(AuthCooldown.remaining(since: sent, now: sent.addingTimeInterval(200)) == 0)
    }

    @Test("a backwards clock cannot extend the cooldown")
    func cooldownClamped() {
        let sent = Date(timeIntervalSince1970: 1_780_000_000)
        let earlier = sent.addingTimeInterval(-300)
        #expect(AuthCooldown.remaining(since: sent, now: earlier) == AuthCooldown.seconds)
    }


    private static func connection(
        status: ConnectionStatus, lastSyncedAt: Date?
    ) -> Connection {
        Connection(
            id: UUID(), institutionId: "200", institutionName: "MeuPluggy",
            status: status, consentExpiresAt: nil, lastSyncedAt: lastSyncedAt,
            lastSyncError: nil, createdAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    @Test("a connection that has never synced reads as setting up, not as broken")
    func firstSyncIsNotAFailure() throws {
        let source = StubSource(
            providers: ["email"],
            connectionList: [Self.connection(status: .needsAction, lastSyncedAt: nil)]
        )
        let row = try #require(source.makeSettingsPayload().banks.first)
        #expect(row.chipText == "Setting up")
        #expect(row.subtitle.contains("First sync"))
        #expect(row.subtitle.contains("Reconnect") == false, "nothing has synced, so there is nothing to resume")
    }

    @Test("a connection that HAS synced before still asks to be reconnected")
    func genuineNeedsActionSurvives() throws {
        let source = StubSource(
            providers: ["email"],
            connectionList: [
                Self.connection(status: .needsAction, lastSyncedAt: Date(timeIntervalSince1970: 1_780_000_000)),
            ]
        )
        let row = try #require(source.makeSettingsPayload().banks.first)
        #expect(row.chipText == "Needs action")
        #expect(row.subtitle.contains("Reconnect"))
    }
}
