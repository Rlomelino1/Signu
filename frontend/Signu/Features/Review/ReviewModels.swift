import Foundation

/// Everything the Review screen (9a) renders, assembled by the provider.
/// 9a is where possible runs are confirmed or dismissed — every decision is
/// made with the charge evidence visible (evidence-before-decision).
struct ReviewPayload {
    var suggestions: [Suggestion]

    struct Suggestion: Identifiable {
        let id: UUID                    // run id
        var subscriptionId: UUID
        var serviceName: String
        /// Green evidence headline — only what the engine measured (copy
        /// honesty). R3: "3 charges, monthly cadence · amounts vary";
        /// R4: "Known subscription service · 1 charge".
        var evidence: String
        var charges: [ChargeLine]       // newest first
        /// Prediction line: renews <date, bare> · ~<amount>.
        var renewsDate: Date
        var renewsAmount: Decimal
        /// R4 asks monthly/annual at confirmation; R3 already measured it.
        var asksIntervalOnTrack: Bool
    }

    struct ChargeLine: Identifiable {
        let id: UUID                    // charge id
        var dateText: String            // "Tue, Jul 07"
        var cardLabel: String           // "Visa 4821"
        var amount: Decimal             // real landed charge — never a tilde
    }
}
