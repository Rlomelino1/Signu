import Testing
import Foundation
@testable import Signu

@Suite("Detail payload (v85)")
@MainActor
struct DetailPayloadTests {

    private struct StubSource: SignuPayloadSource {
        var today: Date
        var now: Date
        var profileValue: Profile!
        var connectionList: [Connection] = []
        var accountList: [BankAccount] = []
        var subscriptionList: [Subscription] = []
        var runList: [SubscriptionRun] = []
        var chargeList: [Charge] = []
        var transactionAccountMap: [UUID: UUID] = [:]
    }

    private static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        SignuCalendar.saoPaulo.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private static func source(
        status: RunStatus,
        nextExpected: Date? = nil,
        endDate: Date? = nil,
        cancelledDate: Date? = nil,
        today: Date = day(2026, 8, 20)
    ) -> (StubSource, UUID) {
        let sub = Subscription(
            id: UUID(), serviceName: "Example Streaming", nickname: nil,
            merchantKey: "example-streaming", category: nil, ignored: false,
            createdAt: day(2026, 5, 1)
        )
        let run = SubscriptionRun(
            id: UUID(), subscriptionId: sub.id, startDate: day(2026, 5, 19),
            endDate: endDate, cancelledDate: cancelledDate, billingInterval: .monthly,
            status: status, detectedBy: .r1, nextExpectedDate: nextExpected
        )
        let charge = Charge(
            id: UUID(), runId: run.id, transactionId: UUID(), date: day(2026, 7, 19),
            amount: 44.44, currency: "BRL", cardLabel: "Master 4321"
        )
        return (
            StubSource(
                today: today, now: today,
                subscriptionList: [sub], runList: [run], chargeList: [charge]
            ),
            sub.id
        )
    }

    // MARK: - The H1 regression

    @Test("an overdue footer names the date the ENGINE would end the run, not expected + 10")
    func overdueFooterMatchesTheEngine() throws {
        let expected = Self.day(2026, 8, 19)
        let (source, id) = Self.source(status: .overdue, nextExpected: expected)
        let payload = try #require(source.makeDetailPayload(subscriptionId: id))
        let footer = try #require(payload.footer)

        let engineDeadline = SignuCalendar.saoPaulo.date(
            byAdding: .day, value: RunLifecycle.deadAfterDays, to: expected
        )!
        #expect(footer.contains(SignuFormat.monthDayShort(engineDeadline)),
                "footer must promise the engine's own deadline: \(footer)")

        let tenDays = SignuCalendar.saoPaulo.date(byAdding: .day, value: 10, to: expected)!
        #expect(!footer.contains(SignuFormat.monthDayShort(tenDays)),
                "expected + 10 is three days before the engine acts — the v-audit H1 bug")
    }

    @Test("the dead date composes the match window with the grace, and is not a bare literal")
    func deadAfterDaysIsComposed() {
        #expect(RunLifecycle.matchWindowDays == 3)
        #expect(RunLifecycle.overdueGraceDays == 10)
        #expect(RunLifecycle.deadAfterDays == 13, "engine: grace starts at expected + match window")
    }

    @Test("an ended run's timeline dates the death at end_date + 13")
    func endedTimelineUsesTheEngineDeadline() throws {
        let paidThrough = Self.day(2026, 8, 19)
        let (source, id) = Self.source(status: .ended, endDate: paidThrough)
        let payload = try #require(source.makeDetailPayload(subscriptionId: id))

        let dead = SignuCalendar.saoPaulo.date(
            byAdding: .day, value: RunLifecycle.deadAfterDays, to: paidThrough
        )!
        let ended = try #require(payload.events.first { $0.title.contains("Ended") })
        #expect(ended.dateText.contains(SignuFormat.timelineDate(dead, referenceYear: 2026)))
    }

    // MARK: - The hero slot, one label per state

    @Test("each run state gets its own hero date label")
    func heroSlotPerState() throws {
        let expected = Self.day(2026, 9, 19)

        let (activeSource, activeId) = Self.source(status: .active, nextExpected: expected)
        let active = try #require(activeSource.makeDetailPayload(subscriptionId: activeId))
        #expect(active.dateSlot.label == "Renews")

        let (overdueSource, overdueId) = Self.source(status: .overdue, nextExpected: Self.day(2026, 8, 19))
        let overdue = try #require(overdueSource.makeDetailPayload(subscriptionId: overdueId))
        #expect(overdue.dateSlot.label == "Expected")

        let (endedSource, endedId) = Self.source(status: .ended, endDate: Self.day(2026, 8, 19))
        let ended = try #require(endedSource.makeDetailPayload(subscriptionId: endedId))
        #expect(ended.dateSlot.label == "Paid through")

        let (cancelledSource, cancelledId) = Self.source(
            status: .cancelled, endDate: Self.day(2026, 8, 19), cancelledDate: Self.day(2026, 8, 1)
        )
        let cancelled = try #require(cancelledSource.makeDetailPayload(subscriptionId: cancelledId))
        #expect(cancelled.dateSlot.label == "Paid through",
                "a cancelled run is dead too, and paid-through is what the user needs")
    }

    @Test("a cancelled run's footer states the cancellation and the paid-through date")
    func cancelledFooter() throws {
        let (source, id) = Self.source(
            status: .cancelled, endDate: Self.day(2026, 8, 19), cancelledDate: Self.day(2026, 8, 1)
        )
        let payload = try #require(source.makeDetailPayload(subscriptionId: id))
        let footer = try #require(payload.footer)
        #expect(footer.contains(SignuFormat.monthDayShort(Self.day(2026, 8, 1))))
        #expect(footer.contains(SignuFormat.monthDayShort(Self.day(2026, 8, 19))))
    }

    @Test("cancel is offered only where the user could have cancelled something")
    func cancelAffordance() throws {
        for status in [RunStatus.active, .overdue] {
            let (source, id) = Self.source(status: status, nextExpected: Self.day(2026, 9, 19))
            let payload = try #require(source.makeDetailPayload(subscriptionId: id))
            #expect(payload.showMarkCancelled, "\(status) should offer cancel")
        }
        for status in [RunStatus.ended, .cancelled] {
            let (source, id) = Self.source(status: status, endDate: Self.day(2026, 8, 19))
            let payload = try #require(source.makeDetailPayload(subscriptionId: id))
            #expect(!payload.showMarkCancelled, "\(status) is already dead")
        }
    }
}
