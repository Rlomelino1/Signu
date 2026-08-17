import Foundation

/// Everything the Review screen (9a) renders, assembled by the provider.
/// 9a is where possible runs are confirmed or dismissed — every decision is
/// made with the charge evidence visible (evidence-before-decision).
struct ReviewPayload {
    var suggestions: [Suggestion]
    /// True when no subscription anywhere has a reminder set — i.e. the feature
    /// has never been used. Half of the rule for offering it after a first
    /// confirmation (22b); the other half is local, see `ReminderOffer`.
    ///
    /// Deliberately not "this is the user's first tracked subscription": R1
    /// auto-confirms without anyone tapping anything, so a user can arrive with
    /// eight tracked subscriptions and never have been asked.
    var remindersNeverUsed = true

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
        ///
        /// **Nil when the run's lifecycle has already ended** — its expected date and
        /// grace period both passed, so there is nothing to predict. It was a
        /// non-optional `Date` until v64, which made `makeReviewPayload` drop such a
        /// suggestion inside a `compactMap` while Home's `suggestionCount` and the Subs
        /// "SUGGESTED" row both still counted it: three surfaces disagreeing, and the
        /// one that could act on it was the one that hid it. Found in production, by
        /// tapping Review and being told "You're all caught up".
        var renewsDate: Date?
        var renewsAmount: Decimal
        /// R4 asks monthly/annual at confirmation; R3 already measured it.
        var asksIntervalOnTrack: Bool
        /// What the engine measured, for the confirmation card that replaces this
        /// row once tracked. On the R4 path the user's answer overrides it, which
        /// is the whole point of the sheet.
        var billingInterval: BillingInterval
    }

    struct ChargeLine: Identifiable {
        let id: UUID                    // charge id
        var dateText: String            // "Tue, Jul 07"
        var cardLabel: String           // "Visa 4821"
        var amount: Decimal             // real landed charge — never a tilde
    }
}
