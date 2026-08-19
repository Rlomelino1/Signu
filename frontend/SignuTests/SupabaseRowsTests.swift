import Testing
import Foundation
@testable import Signu


@Suite("Supabase row decoding")
struct SupabaseRowsTests {


    @Test("a `date` column decodes to the São Paulo calendar day")
    func dateColumn() throws {
        let parsed = try #require("2026-06-19".asPostgresDate)
        let parts = SignuCalendar.saoPaulo.dateComponents([.year, .month, .day], from: parsed)
        #expect(parts.year == 2026)
        #expect(parts.month == 6)
        #expect(parts.day == 19)
    }

    @Test("a timestamptz with SIX fractional digits parses")
    func microsecondTimestamp() {
        #expect("2026-08-10T18:37:13.499725+00:00".asPostgresTimestamp != nil)
    }

    @Test("a timestamptz with no fractional digits also parses")
    func plainTimestamp() {
        #expect("2026-08-10T18:37:13+00:00".asPostgresTimestamp != nil)
    }

    @Test("the Z form of both shapes parses too")
    func zuluTimestamps() {
        #expect("2026-08-10T18:37:13.499Z".asPostgresTimestamp != nil)
        #expect("2026-08-10T18:37:13Z".asPostgresTimestamp != nil)
    }

    @Test("the two date shapes do not decode with each other's parser")
    func shapesAreDistinct() {
        #expect("2026-06-19".asPostgresTimestamp == nil)
        #expect("2026-08-10T18:37:13+00:00".asPostgresDate == nil)
    }


    @Test("money rounds to cents rather than inheriting float error")
    func moneyRounding() {
        #expect(44.44.asMoney == Decimal(string: "44.44"))
        #expect(8.88.asMoney == Decimal(string: "8.88"))
        #expect(0.1.asMoney + 0.2.asMoney == Decimal(string: "0.30"))
    }


    @Test("a foreign charge resolves to the account currency and keeps the original")
    func foreignCharge() {
        let charge = ChargeRow(
            id: UUID(), runId: UUID(), transactionId: UUID(),
            date: "2026-06-19", amount: 8.88, currency: "USD",
            amountInAccountCurrency: 44.44, cardLabel: nil
        ).domain(accountCurrency: "BRL")

        #expect(charge.amount == Decimal(string: "44.44"))
        #expect(charge.currency == "BRL")
        #expect(charge.originalAmount == Decimal(string: "8.88"))
        #expect(charge.originalCurrency == "USD")
        #expect(charge.isForeignCurrency)
    }

    @Test("a domestic charge keeps its own amount and reports no original")
    func domesticCharge() {
        let charge = ChargeRow(
            id: UUID(), runId: UUID(), transactionId: UUID(),
            date: "2026-01-10", amount: 39.90, currency: "BRL",
            amountInAccountCurrency: nil, cardLabel: nil
        ).domain(accountCurrency: "BRL")

        #expect(charge.amount == Decimal(string: "39.90"))
        #expect(charge.currency == "BRL")
        #expect(charge.originalAmount == nil)
        #expect(!charge.isForeignCurrency)
    }

    @Test("a frozen charge with no account keeps its stored currency")
    func frozenCharge() {
        let charge = ChargeRow(
            id: UUID(), runId: UUID(), transactionId: nil,
            date: "2025-09-05", amount: 44.90, currency: "BRL",
            amountInAccountCurrency: nil, cardLabel: "Visa 4821"
        ).domain(accountCurrency: nil)

        #expect(charge.currency == "BRL")
        #expect(charge.transactionId == nil)
    }


    @Test("an unknown connection status degrades to needsAction, never active")
    func unknownStatusIsNotHealthy() {
        let row = ConnectionRow(
            id: UUID(), institutionId: "200", institutionName: "MeuPluggy",
            status: "something_new_from_the_backend",
            consentExpiresAt: nil, lastSyncedAt: nil, providerUpdatedAt: nil,
            lastSyncError: nil,
            createdAt: "2026-08-10T18:37:13.499725+00:00"
        )
        #expect(row.domain.status == .needsAction)
    }
}
