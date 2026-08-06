import Foundation

/// Everything the Subscriptions tab renders, pre-assembled by the provider
/// (subscriptions tab contract, locked 2026-07-15).
struct SubsPayload {
    /// Hero /yr total: Σ(monthly last-charges × 12) + Σ(annual × 1) — no
    /// invented math; invariant under the filter chips; suggestions and
    /// dead subs never enter it.
    var yearlyTotal: Decimal
    /// Tilde propagation: true when any R3/R4 run contributes.
    var yearlyApproximate: Bool
    /// /yr ÷ 12 — derived approximation by construction; always tilde.
    var monthlyCompanion: Decimal

    var allCount: Int
    var activeCount: Int
    var inactiveCount: Int

    /// Non-empty ⇒ SUGGESTED section renders above MONTHLY (9b).
    var suggested: [SuggestedItem]
    var monthly: Group
    var annual: Group
    var inactive: [InactiveItem]

    struct Group {
        var subtotal: Decimal          // native unit — no cross-unit blending
        var approximate: Bool          // any R3/R4 contributor
        var unitSuffix: String         // "/mo" | "/yr"
        var rows: [Row]
    }

    struct Row: Identifiable {
        let id: UUID                   // subscription id
        var serviceName: String
        var subtitle: String           // "Monthly · Master 7730"
        var amount: Decimal            // last charge of latest run
        var approximate: Bool
        var nextDate: Date
        var overdueDays: Int?
        var share: Double              // of the group subtotal (By cost bars)
    }

    struct SuggestedItem: Identifiable {
        let id: UUID                   // run id
        var subscriptionId: UUID
        var serviceName: String
        var evidence: String           // "3 charges · looks monthly · ~R$ 112"
    }

    struct InactiveItem: Identifiable {
        let id: UUID                   // subscription id
        var serviceName: String
        var statusText: String         // "Was R$ 19,90 /mo · last charge Mar 18"
        var paidThroughText: String    // "Paid through Apr 18"
        var cancelled: Bool            // user-asserted vs engine-inferred
    }
}
