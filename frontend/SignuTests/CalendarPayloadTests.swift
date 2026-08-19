import Testing
import Foundation
@testable import Signu


@Suite("Calendar payload")
@MainActor
struct CalendarPayloadTests {

    private func provider() -> MockDataProvider { MockDataProvider() }

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
        let p = provider()
        let payload = try await p.calendarPayload(monthContaining: july)
        let summed = payload.allEntries.reduce(Decimal.zero) { $0 + $1.amount }
        #expect(payload.monthTotal == summed)
    }

    @Test("an overdue run is marked overdue, not treated as upcoming")
    func overdueIsDistinct() async throws {
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


    @Test("the grid is always six rows, whatever the month")
    func gridIsAlwaysSixRows() async throws {
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
        let p = provider()
        let payload = try await p.calendarPayload(monthContaining: july)
        #expect(payload.leadingDays == [28, 29, 30])
        #expect(payload.leadingBlanks == 3, "derived from the days actually rendered")
        #expect(payload.trailingDays.first == 1)
        #expect(payload.trailingDays == Array(1...(42 - 3 - 31)))
    }

    @Test("a month starting on the first weekday has no leading filler")
    func noLeadingFiller() async throws {
        let p = provider()
        let payload = try await p.calendarPayload(monthContaining: MockDataProvider.date(2026, 3, 5))
        #expect(payload.leadingDays.isEmpty)
        #expect(payload.trailingDays.count == 42 - 31)
    }


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
            amount: amount, currency: "BRL", cardLabel: "Master 4321"
        )
    }

    private static func source(
        runStatus: RunStatus,
        nextExpected: Date?,
        chargeDate: Date,
        detectedBy: DetectedBy = .r1,
        ignored: Bool = false,
        today: Date = day(2026, 8, 14)
    ) -> StubSource {
        let sub = Subscription(
            id: UUID(), serviceName: "Example Streaming", nickname: nil,
            merchantKey: "example-streaming", category: nil, ignored: ignored,
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
            chargeList: [charge(run.id, chargeDate, 44.44)]
        )
    }

    @Test("a charge that landed appears in its own month")
    func pastChargeAppears() {
        let source = Self.source(
            runStatus: .active,
            nextExpected: Self.day(2026, 8, 19),
            chargeDate: Self.day(2026, 7, 19)
        )
        let july = source.makeCalendarPayload(monthContaining: Self.day(2026, 7, 1))
        #expect(july.allEntries.count == 1)
        #expect(july.allEntries.first?.kind == .paid)
        #expect(july.allEntries.first?.day == 19)
        #expect(july.monthTotal == 44.44)
    }

    @Test("a cancelled run's charges are still history")
    func cancelledRunsKeepTheirCharges() {
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
        let source = Self.source(
            runStatus: .active, nextExpected: Self.day(2026, 8, 19),
            chargeDate: Self.day(2026, 7, 19), detectedBy: .r3
        )
        let july = source.makeCalendarPayload(monthContaining: Self.day(2026, 7, 1))
        #expect(july.allEntries.first?.approximate == false)
        #expect(july.monthApproximate == false)

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
            chargeDate: Self.day(2026, 8, 19)
        )
        let august = source.makeCalendarPayload(monthContaining: Self.day(2026, 8, 1))
        #expect(august.entriesByDay[19]?.map(\.kind) == [.paid, .expected])
        #expect(Set(august.allEntries.map(\.id)).count == 2)
        #expect(august.monthTotal == 88.88)
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
        #expect(august.monthTotal == 88.88)
    }

    @Test("an overdue forecast is still marked overdue, not paid")
    func overdueSurvivesTheNewPass() {
        let source = Self.source(
            runStatus: .overdue,
            nextExpected: Self.day(2026, 8, 10),
            chargeDate: Self.day(2026, 7, 19)
        )
        let august = source.makeCalendarPayload(monthContaining: Self.day(2026, 8, 1))
        #expect(august.allEntries.map(\.kind) == [.overdue])
        #expect(august.allEntries.first?.overdue == true)
    }
}
