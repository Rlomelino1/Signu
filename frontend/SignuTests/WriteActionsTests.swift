import Testing
import Foundation
@testable import Signu


@Suite("Write actions")
@MainActor
struct WriteActionsTests {

    private func provider() -> MockDataProvider { MockDataProvider() }


    @Test("turning a reminder on is visible in the next payload")
    func reminderOnRoundTrip() async throws {
        let p = provider()
        let sub = try #require(try await p.subscriptions().first)

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
        let p = provider()
        let sub = try #require(try await p.subscriptions().first)
        let before = try #require(try await p.detailPayload(subscriptionId: sub.id))
        try await p.setReminder(subscriptionId: sub.id, remindBeforeDays: 2)

        let after = try #require(try await p.detailPayload(subscriptionId: sub.id))
        #expect(after.reminderOn)
        #expect(after.showRemindMe == before.showRemindMe)
        #expect(after.reminderOn != before.reminderOn)
    }


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
        let p = provider()
        let suggestion = try #require(try await p.reviewPayload().suggestions.first)

        try await p.setIgnored(subscriptionId: suggestion.subscriptionId, ignored: true)

        let settings = try await p.settingsPayload()
        #expect(settings.dismissed.contains { $0.id == suggestion.subscriptionId })
    }

    @Test("restoring puts the suggestion back in review and nothing more")
    func restoreReturnsToReview() async throws {
        let p = provider()
        let suggestion = try #require(try await p.reviewPayload().suggestions.first)
        let id = suggestion.subscriptionId

        try await p.setIgnored(subscriptionId: id, ignored: true)
        try await p.setIgnored(subscriptionId: id, ignored: false)

        #expect(try await p.reviewPayload().suggestions.contains { $0.subscriptionId == id })
        #expect(!(try await p.settingsPayload().dismissed.contains { $0.id == id }))

        let stored = try #require(try await p.subscriptions().first { $0.id == id })
        #expect(!stored.ignored)
        #expect(stored.identification == .auto)
    }

    @Test("a write for an unknown id is a no-op, not a crash")
    func unknownIdIsHarmless() async throws {
        let p = provider()
        let before = try await p.subscriptions()

        try await p.setIgnored(subscriptionId: UUID(), ignored: true)
        try await p.setReminder(subscriptionId: UUID(), remindBeforeDays: 2)

        let after = try await p.subscriptions()
        #expect(after.count == before.count)
        #expect(after.map(\.ignored) == before.map(\.ignored))
        #expect(after.map(\.remindBeforeDays) == before.map(\.remindBeforeDays))
    }
}
