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

    // MARK: - A constant six rows (v46, #10)

    @Test("the grid is always six rows, whatever the month")
    func gridIsAlwaysSixRows() async throws {
        // The property that matters is that the total never changes: a 28-day
        // February from a Sunday would otherwise occupy four rows and a 31-day
        // month from a Saturday six, and the screen under the grid moves.
        let p = provider()
        for month in 1...12 {
            let payload = try await p.calendarPayload(
                monthContaining: MockDataProvider.date(2026, month, 15)
            )
            let cells = payload.leadingDays.count + payload.dayCount + payload.trailingDays.count
            #expect(cells == 42, "\(payload.monthLabel) rendered \(cells) cells")
        }
    }

    @Test("February 2028 — a 29-day leap month still fills six rows")
    func leapFebruary() async throws {
        let p = provider()
        let payload = try await p.calendarPayload(monthContaining: MockDataProvider.date(2028, 2, 10))
        #expect(payload.dayCount == 29)
        #expect(payload.leadingDays.count + payload.dayCount + payload.trailingDays.count == 42)
    }

    @Test("the filler cells carry the adjacent months' real days")
    func fillerDaysAreReal() async throws {
        // July 2026 starts on a Wednesday, so three cells precede it and they are
        // June's last three days — not blanks, and not 1, 2, 3.
        let p = provider()
        let payload = try await p.calendarPayload(monthContaining: july)
        #expect(payload.leadingDays == [28, 29, 30])
        #expect(payload.leadingBlanks == 3, "derived from the days actually rendered")
        #expect(payload.trailingDays.first == 1)
        #expect(payload.trailingDays == Array(1...(42 - 3 - 31)))
    }

    @Test("a month starting on the first weekday has no leading filler")
    func noLeadingFiller() async throws {
        // 1 March 2026 is a Sunday. The empty-range edge: `leadingDays` must come
        // back empty rather than crashing on a reversed range.
        let p = provider()
        let payload = try await p.calendarPayload(monthContaining: MockDataProvider.date(2026, 3, 5))
        #expect(payload.leadingDays.isEmpty)
        #expect(payload.trailingDays.count == 42 - 31)
    }

    // MARK: - What landed, not only what is coming (v46, #4)

    /// Hand-built rather than fixture-driven, so each rule is stated with the
    /// smallest data that can express it — including run states the fixtures do
    /// not happen to contain in the month under test.
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

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        SignuCalendar.saoPaulo.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func charge(_ runId: UUID, _ date: Date, _ amount: Decimal) -> Charge {
        Charge(
            id: UUID(), runId: runId, transactionId: UUID(), date: date,
            amount: amount, currency: "BRL", cardLabel: "Master 2049"
        )
    }

    /// One subscription, one run in the given state, one charge on the 19th.
    private static func source(
        runStatus: RunStatus,
        nextExpected: Date?,
        chargeDate: Date,
        detectedBy: DetectedBy = .r1,
        ignored: Bool = false,
        today: Date = day(2026, 8, 14)
    ) -> StubSource {
        let sub = Subscription(
            id: UUID(), serviceName: "Trueline", nickname: nil,
            merchantKey: "trueline", category: nil, ignored: ignored,
            createdAt: day(2026, 6, 1)
        )
        let run = SubscriptionRun(
            id: UUID(), subscriptionId: sub.id, startDate: day(2026, 6, 19),
            endDate: nil, cancelledDate: nil, billingInterval: .monthly,
            status: runStatus, detectedBy: detectedBy, nextExpectedDate: nextExpected
        )
        return StubSource(
            today: today, now: today,
            subscriptionList: [sub], runList: [run],
            chargeList: [charge(run.id, chargeDate, 34.51)]
        )
    }

    @Test("a charge that landed appears in its own month")
    func pastChargeAppears() {
        // The reported bug: July held a real charge and rendered empty, because
        // only next_expected_date was ever consulted.
        let source = Self.source(
            runStatus: .active,
            nextExpected: Self.day(2026, 8, 19),
            chargeDate: Self.day(2026, 7, 19)
        )
        let july = source.makeCalendarPayload(monthContaining: Self.day(2026, 7, 1))
        #expect(july.allEntries.count == 1)
        #expect(july.allEntries.first?.kind == .paid)
        #expect(july.allEntries.first?.day == 19)
        #expect(july.monthTotal == 34.51)
    }

    @Test("a cancelled run's charges are still history")
    func cancelledRunsKeepTheirCharges() {
        // Money left the account. Scoping the backward pass to active runs the way
        // the forward pass is scoped would report a cheaper past than the ledger.
        for state in [RunStatus.cancelled, .ended] {
            let source = Self.source(
                runStatus: state, nextExpected: nil, chargeDate: Self.day(2026, 7, 19)
            )
            let july = source.makeCalendarPayload(monthContaining: Self.day(2026, 7, 1))
            #expect(july.allEntries.map(\.kind) == [.paid], "\(state) lost its charge")
        }
    }

    @Test("a dismissed subscription's charges stay hidden, past or not")
    func dismissedStayHidden() {
        let source = Self.source(
            runStatus: .active, nextExpected: Self.day(2026, 8, 19),
            chargeDate: Self.day(2026, 7, 19), ignored: true
        )
        #expect(source.makeCalendarPayload(monthContaining: Self.day(2026, 7, 1)).isEmpty)
        #expect(source.makeCalendarPayload(monthContaining: Self.day(2026, 8, 1)).isEmpty)
    }

    @Test("a landed charge is never approximate, even on an R3 run")
    func paidIsNeverApproximate() {
        // The tilde marks a PREDICTED amount. What the bank charged is not a
        // prediction, however the run was detected.
        let source = Self.source(
            runStatus: .active, nextExpected: Self.day(2026, 8, 19),
            chargeDate: Self.day(2026, 7, 19), detectedBy: .r3
        )
        let july = source.makeCalendarPayload(monthContaining: Self.day(2026, 7, 1))
        #expect(july.allEntries.first?.approximate == false)
        #expect(july.monthApproximate == false)

        // …while the expected entry it predicts still carries it.
        let august = source.makeCalendarPayload(monthContaining: Self.day(2026, 8, 1))
        #expect(august.allEntries.first?.kind == .expected)
        #expect(august.allEntries.first?.approximate == true)
        #expect(august.monthApproximate == true)
    }

    @Test("a month holding both a charge and a forecast lists the charge first")
    func paidSortsBeforeExpected() {
        let source = Self.source(
            runStatus: .active,
            nextExpected: Self.day(2026, 8, 19),
            chargeDate: Self.day(2026, 8, 19)   // same day, deliberately
        )
        let august = source.makeCalendarPayload(monthContaining: Self.day(2026, 8, 1))
        #expect(august.entriesByDay[19]?.map(\.kind) == [.paid, .expected])
        // Two entries on one day must survive being Identifiable: the charge is
        // keyed by charge id, the forecast by run id.
        #expect(Set(august.allEntries.map(\.id)).count == 2)
        #expect(august.monthTotal == 69.02)
    }

    @Test("the month total is what was paid plus what is still expected")
    func totalSpansBothKinds() {
        let source = Self.source(
            runStatus: .active,
            nextExpected: Self.day(2026, 8, 19),
            chargeDate: Self.day(2026, 8, 2)
        )
        let august = source.makeCalendarPayload(monthContaining: Self.day(2026, 8, 1))
        #expect(august.allEntries.map(\.kind) == [.paid, .expected])
        #expect(august.monthTotal == 69.02)
    }

    @Test("an overdue forecast is still marked overdue, not paid")
    func overdueSurvivesTheNewPass() {
        let source = Self.source(
            runStatus: .overdue,
            nextExpected: Self.day(2026, 8, 10),      // passed, today is the 14th
            chargeDate: Self.day(2026, 7, 19)
        )
        let august = source.makeCalendarPayload(monthContaining: Self.day(2026, 8, 1))
        #expect(august.allEntries.map(\.kind) == [.overdue])
        #expect(august.allEntries.first?.overdue == true)
    }
}
