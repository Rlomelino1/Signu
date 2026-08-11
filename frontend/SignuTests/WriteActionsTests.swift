import Testing
import Foundation
@testable import Signu

// The app's first write path.
//
// Exercised through `MockDataProvider` because it is the only provider that can be
// driven without a network — and because the mock mutates its fixtures rather than
// no-opping, these assert real round trips: write, then read the payload the screen
// would render. A mock that accepted writes and discarded them would make every one
// of these vacuously pass.
//
// What the live provider adds on top was verified separately against a real
// Postgres carrying Migration #1's grants: `{"remind_before_days": 2}` and `null`
// both land, `{"ignored": true/false}` lands, a write to `service_name` is refused
// 42501 with the value unchanged, and another user's write matches nothing (HTTP
// 200, empty body) because RLS scopes the UPDATE. None of that is reachable from a
// unit test, which is why it was checked by hand and recorded here.

@Suite("Write actions")
@MainActor
struct WriteActionsTests {

    private func provider() -> MockDataProvider { MockDataProvider() }

    // MARK: - The reminder toggle

    @Test("turning a reminder on is visible in the next payload")
    func reminderOnRoundTrip() async throws {
        let p = provider()
        let sub = try #require(try await p.subscriptions().first)

        // Before: the fixtures ship with reminders off, so this also pins the
        // starting state the toggle is seeded from.
        let before = try #require(try await p.detailPayload(subscriptionId: sub.id))
        #expect(!before.reminderOn)

        try await p.setReminder(subscriptionId: sub.id, remindBeforeDays: 2)

        let after = try #require(try await p.detailPayload(subscriptionId: sub.id))
        #expect(after.reminderOn)
    }

    @Test("turning it off writes nil, because the nullable column is the switch")
    func reminderOffWritesNil() async throws {
        let p = provider()
        let sub = try #require(try await p.subscriptions().first)

        try await p.setReminder(subscriptionId: sub.id, remindBeforeDays: 2)
        try await p.setReminder(subscriptionId: sub.id, remindBeforeDays: nil)

        let stored = try #require(try await p.subscriptions().first { $0.id == sub.id })
        #expect(stored.remindBeforeDays == nil)
        #expect(try #require(try await p.detailPayload(subscriptionId: sub.id)).reminderOn == false)
    }

    @Test("reminderOn is independent of whether the button is offered")
    func reminderOnIsNotShowRemindMe() async throws {
        // showRemindMe tracks the run's status; reminderOn tracks the stored
        // setting. Conflating them is what made the toggle always start "off" —
        // the first tap on an already-on reminder turned it off while the label
        // said it had turned on.
        let p = provider()
        let sub = try #require(try await p.subscriptions().first)
        let before = try #require(try await p.detailPayload(subscriptionId: sub.id))
        try await p.setReminder(subscriptionId: sub.id, remindBeforeDays: 2)

        let after = try #require(try await p.detailPayload(subscriptionId: sub.id))
        #expect(after.reminderOn)
        // The claim, stated so it can fail: setting a reminder changes the LABEL and
        // not whether the button is offered. If the two were ever collapsed into one
        // field this would break.
        #expect(after.showRemindMe == before.showRemindMe)
        #expect(after.reminderOn != before.reminderOn)
    }

    // MARK: - Dismiss and restore

    @Test("dismissing a suggestion removes it from review")
    func dismissLeavesReview() async throws {
        let p = provider()
        let review = try await p.reviewPayload()
        let suggestion = try #require(review.suggestions.first)

        try await p.setIgnored(subscriptionId: suggestion.subscriptionId, ignored: true)

        let after = try await p.reviewPayload()
        #expect(!after.suggestions.contains { $0.subscriptionId == suggestion.subscriptionId })
        #expect(after.suggestions.count == review.suggestions.count - 1)
    }

    @Test("a dismissed suggestion appears in Settings, ready to restore")
    func dismissedIsRecoverable() async throws {
        // The "recoverable in Settings" promise the review contract makes. Before
        // the write path this list could only ever show fixtures, never something
        // the user had just dismissed.
        let p = provider()
        let suggestion = try #require(try await p.reviewPayload().suggestions.first)

        try await p.setIgnored(subscriptionId: suggestion.subscriptionId, ignored: true)

        let settings = try await p.settingsPayload()
        #expect(settings.dismissed.contains { $0.id == suggestion.subscriptionId })
    }

    @Test("restoring puts the suggestion back in review and nothing more")
    func restoreReturnsToReview() async throws {
        // Restore is `ignored = false` exactly: the run returns to `possible` and
        // resurfaces, because it never left that state. It must NOT start tracking.
        let p = provider()
        let suggestion = try #require(try await p.reviewPayload().suggestions.first)
        let id = suggestion.subscriptionId

        try await p.setIgnored(subscriptionId: id, ignored: true)
        try await p.setIgnored(subscriptionId: id, ignored: false)

        #expect(try await p.reviewPayload().suggestions.contains { $0.subscriptionId == id })
        #expect(!(try await p.settingsPayload().dismissed.contains { $0.id == id }))

        let stored = try #require(try await p.subscriptions().first { $0.id == id })
        #expect(!stored.ignored)
        // Still a suggestion, not a tracked subscription: restore does not confirm.
        #expect(stored.identification == .auto)
    }

    @Test("a write for an unknown id is a no-op, not a crash")
    func unknownIdIsHarmless() async throws {
        let p = provider()
        let before = try await p.subscriptions()

        try await p.setIgnored(subscriptionId: UUID(), ignored: true)
        try await p.setReminder(subscriptionId: UUID(), remindBeforeDays: 2)

        // Nothing moved. Live, this is the RLS case: a row the user cannot see
        // matches nothing and returns success with an empty body — verified against
        // a real Postgres. The mock mirrors that rather than trapping, so the two
        // providers agree about a miss.
        let after = try await p.subscriptions()
        #expect(after.count == before.count)
        #expect(after.map(\.ignored) == before.map(\.ignored))
        #expect(after.map(\.remindBeforeDays) == before.map(\.remindBeforeDays))
    }
}
