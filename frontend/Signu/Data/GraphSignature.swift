import Foundation

/// A cheap fingerprint of everything the screens render, used to answer one
/// question: did a re-read actually find anything?
///
/// The answer decides whether a foreground refresh rebuilds the visible tab.
/// Getting it wrong is invisible in both directions and bad in both: a signature
/// that always changes throws away the user's scroll position every time they
/// switch apps, and one that never changes leaves the app rendering yesterday.
///
/// **Counts alone are not enough**, which is the trap this exists to avoid. The
/// changes a background sync produces most often move no row in or out: a run
/// flipping to `overdue`, a renewal date sliding a week, a charge landing on an
/// existing run. So statuses and dates are folded in as well.
///
/// It will still miss a change to a field nothing renders — which is the correct
/// thing to miss, since rebuilding a screen for it would be work with no visible
/// result.
enum GraphSignature {

    static func of(
        connections: [Connection],
        accounts: [BankAccount],
        subscriptions: [Subscription],
        runs: [SubscriptionRun],
        charges: [Charge]
    ) -> Int {
        var hasher = Hasher()
        for connection in connections {
            hasher.combine(connection.id)
            hasher.combine(connection.status)
            hasher.combine(connection.lastSyncedAt)
        }
        for account in accounts {
            hasher.combine(account.id)
            hasher.combine(account.nickname)
        }
        for subscription in subscriptions {
            hasher.combine(subscription.id)
            // Every user-owned column, because each one renders somewhere.
            hasher.combine(subscription.nickname)
            hasher.combine(subscription.category)
            hasher.combine(subscription.ignored)
            hasher.combine(subscription.remindBeforeDays)
        }
        for run in runs {
            hasher.combine(run.id)
            hasher.combine(run.status)
            hasher.combine(run.nextExpectedDate)
            hasher.combine(run.endDate)
            hasher.combine(run.cancelledDate)
        }
        for charge in charges {
            hasher.combine(charge.id)
            hasher.combine(charge.amount)
            hasher.combine(charge.date)
        }
        return hasher.finalize()
    }
}
