import Testing
import Foundation
@testable import Signu

// Home's watching state carrying suggestions (22a).
//
// The defect this closes: `homeContent` picks `.watching` precisely when no run
// has a status other than `possible` — and a `possible` run IS a suggestion. So
// the one screen guaranteed to be holding suggestions was the one saying nothing
// had been detected, with no way in to the review screen where they are decided.

@Suite("Suggestions on Home")
@MainActor
struct SuggestionsOnHomeTests {

    // MARK: - The copy rules, tested where they are decidable

    @Test("one, two, and more than two")
    func namingRule() {
        #expect(HomePayload.suggestionNames([]) == "")
        #expect(HomePayload.suggestionNames(["iFood Clube"]) == "iFood Clube")
        #expect(HomePayload.suggestionNames(["iFood Clube", "MUBI"]) == "iFood Clube and MUBI")
        #expect(
            HomePayload.suggestionNames(["iFood Clube", "MUBI", "Spotify", "Netflix", "Duolingo"])
                == "iFood Clube, MUBI and 3 more"
        )
    }

    @Test("the remainder is counted, never truncated silently")
    func remainderIsCounted() {
        // Two names plus "and N more" must always account for every suggestion,
        // because the same number renders in the badge beside the sentence.
        for total in 3...9 {
            let names = (1...total).map { "Service \($0)" }
            let line = HomePayload.suggestionNames(names)
            #expect(line.hasSuffix("and \(total - 2) more"), "\(line)")
        }
    }

    @Test("the verb agrees with the count")
    func verbAgreement() {
        // "iFood Clube look recurring" reads as a bug rather than as copy.
        #expect(HomePayload.suggestionLine(["iFood Clube"])?.contains("looks recurring") == true)
        #expect(HomePayload.suggestionLine(["iFood Clube", "MUBI"])?.contains("look recurring") == true)
        #expect(HomePayload.suggestionLine([]) == nil)
    }

    // MARK: - The payload

    private func watching(_ p: MockDataProvider) async throws -> HomePayload.Watching {
        let payload = try await p.homePayload()
        guard case .watching(let watching) = payload.content else {
            Issue.record("expected the watching state, got \(payload.content)")
            throw CancellationError()
        }
        return watching
    }

    @Test("suggestions reach Home, with a way to act on them")
    func suggestionsReachHome() async throws {
        let p = MockDataProvider(scenario: .suggestionsOnly)
        let state = try await watching(p)

        #expect(state.suggestionCount == 2)
        #expect(state.suggestionLine != nil)
        // The claim that was false before 22a: this screen knows what was found.
        let names = try await p.reviewPayload().suggestions.map(\.serviceName).sorted()
        for name in names {
            #expect(state.suggestionLine?.contains(name) == true, "\(name)")
        }
    }

    @Test("the headline distinguishes found from confirmed")
    func headlineDistinguishes() async throws {
        // "detected" is a claim about the engine; "confirmed" is about the user.
        // Saying none were detected while holding two was the defect.
        let withSuggestions = try await watching(MockDataProvider(scenario: .suggestionsOnly))
        #expect(withSuggestions.headline == "No confirmed subscriptions yet")

        let empty = try await watching(MockDataProvider(scenario: .freshConnection))
        #expect(empty.headline == "No subscriptions detected yet")
        #expect(empty.suggestionCount == 0)
        #expect(empty.suggestionLine == nil)
    }

    @Test("dismissing every suggestion empties the card and the dot")
    func dismissingClearsIt() async throws {
        // The rule the tab dot follows: it clears at zero, so acting clears it and
        // looking does not. Dismissing is acting — "not a subscription" is a
        // decision.
        let p = MockDataProvider(scenario: .suggestionsOnly)
        for suggestion in try await p.reviewPayload().suggestions {
            try await p.setIgnored(subscriptionId: suggestion.subscriptionId, ignored: true)
        }

        let state = try await watching(p)
        #expect(state.suggestionCount == 0)
        #expect(state.suggestionLine == nil)
        #expect(state.headline == "No subscriptions detected yet")
    }

    @Test("confirming one leaves the other, and takes Home out of watching")
    func confirmingOneMovesOn() async throws {
        // A confirmed run is no longer `possible`, so the screen stops being the
        // watching state at all — which is the correct exit, not a special case.
        let p = MockDataProvider(scenario: .suggestionsOnly)
        let first = try #require(try await p.reviewPayload().suggestions.first)
        try await p.confirmSuggestion(runId: first.id, billingInterval: .monthly)

        let payload = try await p.homePayload()
        guard case .active = payload.content else {
            Issue.record("confirming should move Home to its active state")
            return
        }
        #expect(try await p.reviewPayload().suggestions.count == 1)
    }

    @Test("a renamed suggestion is named by its nickname")
    func namesFollowTheDisplayName() async throws {
        let p = MockDataProvider(scenario: .suggestionsOnly)
        let first = try #require(try await p.reviewPayload().suggestions.first)
        try await p.setNickname(subscriptionId: first.subscriptionId, nickname: "Aardvark")

        // Sorted, so the rename lands first and proves the line reads displayName
        // rather than the engine's service_name.
        let state = try await watching(p)
        #expect(state.suggestionLine?.hasPrefix("Aardvark") == true, "\(state.suggestionLine ?? "nil")")
    }
}
