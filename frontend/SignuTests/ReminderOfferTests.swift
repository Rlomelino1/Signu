import Testing
import Foundation
@testable import Signu

// When the reminder offer is made (22b).
//
// The rule has two halves because the two answers are stored differently. "Yes"
// is durable in the database — the subscription now carries a
// `remind_before_days`, so the feature has demonstrably been met, on every
// device, forever. "No" writes nothing, deliberately: declining a reminder must
// not leave a mark on a row the user did not ask to change, so the only record
// of it is local. This suite covers the half the payload can see.

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
        // The question is whether the user has met the feature, not whether the
        // subscription is still visible. Scoping this to non-ignored rows would
        // re-introduce the offer to someone who already knows about it.
        let p = MockDataProvider()
        let dismissed = try #require(try await p.subscriptions().first(where: \.ignored))
        try await p.setReminder(subscriptionId: dismissed.id, remindBeforeDays: 2)
        #expect(try await p.reviewPayload().remindersNeverUsed == false)
    }

    @Test("turning a reminder back off restores the offer")
    func turningOffRestoresIt() async throws {
        // Correct rather than clever: with nothing carrying a reminder the
        // database can no longer say the feature has been met. The local flag is
        // what stops the offer returning for someone who DECLINED, and someone
        // who turned a reminder on and then off has declined nothing.
        let p = MockDataProvider()
        let sub = try #require(try await p.subscriptions().first)
        try await p.setReminder(subscriptionId: sub.id, remindBeforeDays: 2)
        try await p.setReminder(subscriptionId: sub.id, remindBeforeDays: nil)
        #expect(try await p.reviewPayload().remindersNeverUsed)
    }

    @Test("suggestions carry the interval their confirmation card renders")
    func suggestionsCarryTheInterval() async throws {
        // The card says "Monthly · renews …" the instant a row is confirmed, so
        // the interval has to be in the payload rather than parsed back out of
        // the evidence sentence.
        let p = MockDataProvider()
        let suggestions = try await p.reviewPayload().suggestions
        #expect(!suggestions.isEmpty)
        for suggestion in suggestions {
            #expect([BillingInterval.monthly, .annual].contains(suggestion.billingInterval))
        }
    }
}
