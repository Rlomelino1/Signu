import Foundation


extension MockDataProvider {
    static func demoCancelledTrailing() -> (Subscription, [SubscriptionRun], [Charge]) {
        let sub = Subscription(
            id: UUID(), serviceName: "Netflix", nickname: nil, merchantKey: "netflix",
            category: "Streaming", identification: .auto, ignored: false,
            remindBeforeDays: nil, createdAt: date(2023, 11, 18)
        )
        let runId = UUID()
        let run = SubscriptionRun(
            id: runId, subscriptionId: sub.id,
            startDate: date(2023, 11, 18), endDate: date(2026, 8, 18),
            cancelledDate: date(2026, 7, 2), billingInterval: .monthly,
            status: .cancelled, detectedBy: .r1, nextExpectedDate: nil
        )
        var charges: [Charge] = []
        var d = date(2024, 1, 18)
        while d <= date(2026, 6, 18) {
            charges.append(Charge(id: UUID(), runId: runId, transactionId: nil, date: d,
                                  amount: brl("44.90"), currency: "BRL", cardLabel: "Visa 4821"))
            d = calendar.date(byAdding: .month, value: 1, to: d)!
        }
        charges.append(Charge(id: UUID(), runId: runId, transactionId: nil, date: date(2026, 7, 18),
                              amount: brl("44.90"), currency: "BRL", cardLabel: "Visa 4821"))
        return (sub, [run], charges)
    }
}
