import Foundation

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
