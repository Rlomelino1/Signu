import Testing
import Foundation
@testable import Signu

// What a re-read counts as "something changed" (v35).
//
// This decides whether returning to the app rebuilds the visible tab. Both wrong
// answers are silent: always-changed throws away the user's scroll position on
// every app switch, never-changed leaves the app rendering yesterday's state
// after the 15:30 UTC sync has moved everything.

@Suite("Graph signature")
@MainActor
struct GraphSignatureTests {

    private func signature(_ p: MockDataProvider) async throws -> Int {
        GraphSignature.of(
            connections: try await p.connections(),
            accounts: try await p.bankAccounts(),
            subscriptions: try await p.subscriptions(),
            runs: try await p.subscriptions().asyncRuns(p),
            charges: try await p.subscriptions().asyncCharges(p)
        )
    }

    @Test("the same graph signs the same, twice")
    func stable() async throws {
        let p = MockDataProvider()
        #expect(try await signature(p) == (try await signature(p)))
    }

    @Test("two different datasets sign differently")
    func discriminates() async throws {
        let full = try await signature(MockDataProvider())
        let empty = try await signature(MockDataProvider(scenario: .noBank))
        #expect(full != empty)
    }

    // MARK: - The changes a background sync actually produces

    @Test("a run going overdue is a change, though no row moves")
    func statusChangeCounts() async throws {
        // The trap this guards: counts alone would call this identical, and
        // overdue is the state the user most needs to see arrive.
        let p = MockDataProvider()
        let before = try await signature(p)
        var runs = try await allRuns(p)
        runs[0].status = .overdue
        let after = GraphSignature.of(
            connections: try await p.connections(),
            accounts: try await p.bankAccounts(),
            subscriptions: try await p.subscriptions(),
            runs: runs,
            charges: try await allCharges(p)
        )
        #expect(before != after)
    }

    @Test("a renewal date sliding is a change")
    func dateChangeCounts() async throws {
        let p = MockDataProvider()
        let before = try await signature(p)
        var runs = try await allRuns(p)
        runs[0].nextExpectedDate = runs[0].nextExpectedDate.map { $0.addingTimeInterval(86_400) }
        let after = GraphSignature.of(
            connections: try await p.connections(),
            accounts: try await p.bankAccounts(),
            subscriptions: try await p.subscriptions(),
            runs: runs,
            charges: try await allCharges(p)
        )
        #expect(before != after)
    }

    @Test("a user-owned column changing is a change")
    func userColumnsCount() async throws {
        // Not a sync's doing, but the same refresh path carries a write made on
        // another device, and every one of these renders somewhere.
        let p = MockDataProvider()
        let before = try await signature(p)
        let sub = try #require(try await p.subscriptions().first)
        try await p.setNickname(subscriptionId: sub.id, nickname: "Renamed")
        #expect(try await signature(p) != before)
    }

    @Test("a charge landing on an existing run is a change")
    func chargeCounts() async throws {
        let p = MockDataProvider()
        let before = try await signature(p)
        var charges = try await allCharges(p)
        charges.removeFirst()
        let after = GraphSignature.of(
            connections: try await p.connections(),
            accounts: try await p.bankAccounts(),
            subscriptions: try await p.subscriptions(),
            runs: try await allRuns(p),
            charges: charges
        )
        #expect(before != after)
    }

    // MARK: - Helpers

    private func allRuns(_ p: MockDataProvider) async throws -> [SubscriptionRun] {
        var out: [SubscriptionRun] = []
        for sub in try await p.subscriptions() { out += try await p.runs(subscriptionId: sub.id) }
        return out
    }

    private func allCharges(_ p: MockDataProvider) async throws -> [Charge] {
        var out: [Charge] = []
        for run in try await allRuns(p) { out += try await p.charges(runId: run.id) }
        return out
    }
}

private extension Array where Element == Subscription {
    @MainActor
    func asyncRuns(_ p: MockDataProvider) async throws -> [SubscriptionRun] {
        var out: [SubscriptionRun] = []
        for sub in self { out += try await p.runs(subscriptionId: sub.id) }
        return out
    }

    @MainActor
    func asyncCharges(_ p: MockDataProvider) async throws -> [Charge] {
        var out: [Charge] = []
        for run in try await asyncRuns(p) { out += try await p.charges(runId: run.id) }
        return out
    }
}
