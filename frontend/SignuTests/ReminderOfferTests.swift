import Testing
import Foundation
@testable import Signu


@Suite("Reminder offer")
@MainActor
struct ReminderOfferTests {

    @Test("the fixtures have never used reminders")
    func startsUnused() async throws {
        let p = MockDataProvider()
        #expect(try await p.reviewPayload().remindersNeverUsed)
    }

    @Test("one reminder anywhere ends the offer")
    func anyReminderEndsIt() async throws {
        let p = MockDataProvider()
        let sub = try #require(try await p.subscriptions().first)
        try await p.setReminder(subscriptionId: sub.id, remindBeforeDays: 2)
        #expect(try await p.reviewPayload().remindersNeverUsed == false)
    }

    @Test("a reminder on a dismissed subscription counts too")
    func dismissedCounts() async throws {
        let p = MockDataProvider()
        let dismissed = try #require(try await p.subscriptions().first(where: \.ignored))
        try await p.setReminder(subscriptionId: dismissed.id, remindBeforeDays: 2)
        #expect(try await p.reviewPayload().remindersNeverUsed == false)
    }

    @Test("turning a reminder back off restores the offer")
    func turningOffRestoresIt() async throws {
        let p = MockDataProvider()
        let sub = try #require(try await p.subscriptions().first)
        try await p.setReminder(subscriptionId: sub.id, remindBeforeDays: 2)
        try await p.setReminder(subscriptionId: sub.id, remindBeforeDays: nil)
        #expect(try await p.reviewPayload().remindersNeverUsed)
    }

    @Test("suggestions carry the interval their confirmation card renders")
    func suggestionsCarryTheInterval() async throws {
        let p = MockDataProvider()
        let suggestions = try await p.reviewPayload().suggestions
        #expect(!suggestions.isEmpty)
        for suggestion in suggestions {
            #expect([BillingInterval.monthly, .annual].contains(suggestion.billingInterval))
        }
    }
}
