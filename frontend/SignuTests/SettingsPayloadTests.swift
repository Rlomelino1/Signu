import Testing
import Foundation
@testable import Signu

// The v19 password row is state-driven, and the state is derived from the auth
// identities. That derivation is the part that can silently invert — rendering
// "Change password" to a Google-only account sends them off to change a password
// they never had — so it is pinned here rather than left to a screenshot.

/// The smallest thing that satisfies `SignuPayloadSource`, so `makeSettingsPayload`
/// runs for real instead of the test asserting against a reimplementation of it.
/// Only the profile varies; every list is empty, which also exercises the 12d
/// empty-banks shape.
private struct StubSource: SignuPayloadSource {
    var providers: [String]

    var today = Date(timeIntervalSince1970: 1_780_000_000)
    var now = Date(timeIntervalSince1970: 1_780_000_000)
    var profileValue: Profile! {
        Profile(
            id: UUID(),
            displayName: "Rafael Souza",
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

/// `@MainActor` because `SignuPayloadSource` is: the payload boundary is
/// main-actor isolated, so the tests that exercise it run there too. This is the
/// isolation being *checked* rather than assumed — the reason the protocols were
/// annotated in the first place.
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
        // `providerLabel` renders "email" as "Password". Matching on that display
        // string would pass today and invert the day the copy changes — and the
        // failure is silent, because both branches render a plausible row.
        let payload = StubSource(providers: ["email"]).makeSettingsPayload()
        #expect(payload.hasPassword)
        #expect(payload.providers == ["Password"])
        #expect(!payload.providers.contains("email"))
    }

    @Test("an identity provider nobody has mapped yet still renders")
    func unknownProvider() {
        // Supabase can return apple, azure, github… An unmapped provider must not
        // vanish from the chips: the row above it claims to list how you sign in.
        let payload = StubSource(providers: ["apple"]).makeSettingsPayload()
        #expect(payload.providers == ["Apple"])
        #expect(!payload.hasPassword)
    }

    @Test("one cooldown constant, so the three surfaces cannot drift")
    func oneCooldown() {
        // Supabase rate-limits the reset endpoint at ~60s. A surface that drifted
        // below that fails silently — the send swallows its errors by contract.
        #expect(AuthCooldown.seconds >= 60)
    }

    @Test("the cooldown is computed from elapsed time, not counted down")
    func cooldownRemaining() {
        let sent = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(AuthCooldown.remaining(since: nil, now: sent) == 0)
        #expect(AuthCooldown.remaining(since: sent, now: sent) == AuthCooldown.seconds)
        // The property the timestamp buys: time spent on another tab still counts.
        // A decrementing counter would read 120 here, because nothing ticked it.
        #expect(AuthCooldown.remaining(since: sent, now: sent.addingTimeInterval(60)) == 60)
        #expect(AuthCooldown.remaining(since: sent, now: sent.addingTimeInterval(200)) == 0)
    }

    @Test("a backwards clock cannot extend the cooldown")
    func cooldownClamped() {
        let sent = Date(timeIntervalSince1970: 1_780_000_000)
        // NTP correction, or a user changing the device clock. Without the upper
        // clamp this reads 420s and strands the row.
        let earlier = sent.addingTimeInterval(-300)
        #expect(AuthCooldown.remaining(since: sent, now: earlier) == AuthCooldown.seconds)
    }
}
