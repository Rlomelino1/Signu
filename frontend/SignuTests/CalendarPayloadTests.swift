import Testing
import Foundation
@testable import Signu

// The renewal calendar's assembly (v32).
//
// Unit-tested rather than left to the UI tests because the grid's arithmetic is
// where this shape of screen goes wrong: an off-by-one in the leading offset
// renders every date on the wrong weekday and still looks like a calendar.

@Suite("Calendar payload")
@MainActor
struct CalendarPayloadTests {

    private func provider() -> MockDataProvider { MockDataProvider() }

    /// The fixtures pin today to Monday, 13 July 2026.
    private var july: Date { MockDataProvider.date(2026, 7, 13) }

    @Test("the month opens on today and marks it")
    func opensOnToday() async throws {
        let p = provider()
        let payload = try await p.calendarPayload(monthContaining: july)
        #expect(payload.monthLabel == "July 2026")
        #expect(payload.dayCount == 31)
        #expect(payload.todayDay == 13)
    }

    @Test("the leading offset puts the 1st on its real weekday")
    func leadingOffsetIsRight() async throws {
        // 1 July 2026 is a Wednesday, and the grid is Sunday-first, so three
        // blanks precede it. This is the assertion that catches a whole calendar
        // rendered a day out.
        let p = provider()
        let payload = try await p.calendarPayload(monthContaining: july)
        #expect(payload.leadingBlanks == 3)
    }

    @Test("a month the user pages to has no today")
    func todayIsMonthSpecific() async throws {
        let p = provider()
        let august = try await p.calendarPayload(monthContaining: MockDataProvider.date(2026, 8, 4))
        #expect(august.todayDay == nil)
        #expect(august.monthLabel == "August 2026")
    }

    @Test("only renewals inside the month are listed")
    func entriesAreScopedToTheMonth() async throws {
        let p = provider()
        let payload = try await p.calendarPayload(monthContaining: july)
        let calendar = SignuCalendar.saoPaulo
        for entry in payload.allEntries {
            #expect(calendar.isDate(entry.date, equalTo: payload.monthStart, toGranularity: .month))
            #expect(entry.day == calendar.component(.day, from: entry.date))
        }
    }

    @Test("the month total is the sum of what it lists")
    func totalMatchesTheEntries() async throws {
        // Checkable on screen, the same instinct as 13a's header arithmetic: the
        // figure at the top must equal the rows under it.
        let p = provider()
        let payload = try await p.calendarPayload(monthContaining: july)
        let summed = payload.allEntries.reduce(Decimal.zero) { $0 + $1.amount }
        #expect(payload.monthTotal == summed)
    }

    @Test("an overdue run is marked overdue, not treated as upcoming")
    func overdueIsDistinct() async throws {
        // The fixtures ship one overdue subscription. A missed renewal must not
        // render as a future one.
        let p = provider()
        var found = false
        for month in [MockDataProvider.date(2026, 6, 1), july] {
            let payload = try await p.calendarPayload(monthContaining: month)
            if payload.allEntries.contains(where: \.overdue) { found = true }
        }
        #expect(found, "the fixtures' overdue run should appear, flagged")
    }

    @Test("dismissed subscriptions never appear")
    func dismissedAreExcluded() async throws {
        // Same visibility rule as every other payload: the user said it is not a
        // subscription, so it is not a renewal either.
        let p = provider()
        let dismissed = try #require(try await p.subscriptions().first(where: \.ignored))
        for month in [MockDataProvider.date(2026, 6, 1), july, MockDataProvider.date(2026, 8, 1)] {
            let payload = try await p.calendarPayload(monthContaining: month)
            #expect(!payload.allEntries.contains { $0.subscriptionId == dismissed.id })
        }
    }

    @Test("a renamed subscription shows its nickname")
    func rowsUseTheDisplayName() async throws {
        let p = provider()
        let sub = try #require(try await p.subscriptions().first { !$0.ignored })
        try await p.setNickname(subscriptionId: sub.id, nickname: "My thing")

        for month in [july, MockDataProvider.date(2026, 8, 1)] {
            let payload = try await p.calendarPayload(monthContaining: month)
            if let row = payload.allEntries.first(where: { $0.subscriptionId == sub.id }) {
                #expect(row.serviceName == "My thing")
                return
            }
        }
    }
}
