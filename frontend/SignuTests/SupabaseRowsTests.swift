import Testing
import Foundation
@testable import Signu

// The decoding boundary, which is where the live provider's real risks live.
//
// Every case here is a trap that actually bit, or would have, while wiring the
// provider — not invented coverage. Each one was previously verified by hand
// against production and then had nothing holding it in place.

@Suite("Supabase row decoding")
struct SupabaseRowsTests {

    // MARK: - Dates

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
        // Production returns exactly this shape. ISO8601DateFormatter is classically
        // limited to three fractional digits, and a silent nil here would have made
        // every createdAt .distantPast and rendered as garbage "tracking since".
        #expect("2026-08-10T18:37:13.499725+00:00".asPostgresTimestamp != nil)
    }

    @Test("a timestamptz with no fractional digits also parses")
    func plainTimestamp() {
        // Covered by the second formatter. One strategy cannot read both shapes,
        // which is why the fallback exists.
        #expect("2026-08-10T18:37:13+00:00".asPostgresTimestamp != nil)
    }

    @Test("the two date shapes do not decode with each other's parser")
    func shapesAreDistinct() {
        #expect("2026-06-19".asPostgresTimestamp == nil)
        #expect("2026-08-10T18:37:13+00:00".asPostgresDate == nil)
    }

    // MARK: - Money

    @Test("money rounds to cents rather than inheriting float error")
    func moneyRounding() {
        // JSON number -> Decimal goes via Double and can yield 34.510000000000002,
        // which would render. Same class of artefact as the v23 epsilon bug.
        #expect(34.51.asMoney == Decimal(string: "34.51"))
        #expect(6.45.asMoney == Decimal(string: "6.45"))
        #expect(0.1.asMoney + 0.2.asMoney == Decimal(string: "0.30"))
    }

    // MARK: - The currency coalesce

    @Test("a foreign charge resolves to the account currency and keeps the original")
    func foreignCharge() {
        // The real Steam charge. Without this the UI renders R$6.45 instead of
        // R$34.51 — wrong by 5.3x, because the formatter hardcodes BRL.
        let charge = ChargeRow(
            id: UUID(), runId: UUID(), transactionId: UUID(),
            date: "2026-06-19", amount: 6.45, currency: "USD",
            amountInAccountCurrency: 34.51, cardLabel: nil
        ).domain(accountCurrency: "BRL")

        #expect(charge.amount == Decimal(string: "34.51"))
        #expect(charge.currency == "BRL")
        #expect(charge.originalAmount == Decimal(string: "6.45"))
        #expect(charge.originalCurrency == "USD")
        #expect(charge.isForeignCurrency)
    }

    @Test("a domestic charge keeps its own amount and reports no original")
    func domesticCharge() {
        // amount_in_account_currency is null exactly when `currency` already IS the
        // account currency — verified across all 258 real rows, zero violations.
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
        // transaction_id is null once the bank link is removed, so no account can be
        // resolved. The stored currency is the best statement available about it.
        let charge = ChargeRow(
            id: UUID(), runId: UUID(), transactionId: nil,
            date: "2025-09-05", amount: 44.90, currency: "BRL",
            amountInAccountCurrency: nil, cardLabel: "Visa 4821"
        ).domain(accountCurrency: nil)

        #expect(charge.currency == "BRL")
        #expect(charge.transactionId == nil)
    }

    // MARK: - Enum fallbacks

    @Test("an unknown connection status degrades to needsAction, never active")
    func unknownStatusIsNotHealthy() {
        let row = ConnectionRow(
            id: UUID(), institutionId: "200", institutionName: "MeuPluggy",
            status: "something_new_from_the_backend",
            consentExpiresAt: nil, lastSyncedAt: nil, lastSyncError: nil,
            createdAt: "2026-08-10T18:37:13.499725+00:00"
        )
        // Presenting an unrecognised state as healthy is the failure that matters.
        #expect(row.domain.status == .needsAction)
    }
}
