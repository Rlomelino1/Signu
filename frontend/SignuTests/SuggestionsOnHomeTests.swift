import Testing
import Foundation
@testable import Signu


@Suite("Suggestions on Home")
@MainActor
struct SuggestionsOnHomeTests {


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
        for total in 3...9 {
            let names = (1...total).map { "Service \($0)" }
            let line = HomePayload.suggestionNames(names)
            #expect(line.hasSuffix("and \(total - 2) more"), "\(line)")
        }
    }

    @Test("the verb agrees with the count")
    func verbAgreement() {
        #expect(HomePayload.suggestionLine(["iFood Clube"])?.contains("looks recurring") == true)
        #expect(HomePayload.suggestionLine(["iFood Clube", "MUBI"])?.contains("look recurring") == true)
        #expect(HomePayload.suggestionLine([]) == nil)
    }


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
        let names = try await p.reviewPayload().suggestions.map(\.serviceName).sorted()
        for name in names {
            #expect(state.suggestionLine?.contains(name) == true, "\(name)")
        }
    }

    @Test("the headline distinguishes found from confirmed")
    func headlineDistinguishes() async throws {
        let withSuggestions = try await watching(MockDataProvider(scenario: .suggestionsOnly))
        #expect(withSuggestions.headline == "No confirmed subscriptions yet")

        let empty = try await watching(MockDataProvider(scenario: .freshConnection))
        #expect(empty.headline == "No subscriptions detected yet")
        #expect(empty.suggestionCount == 0)
        #expect(empty.suggestionLine == nil)
    }

    @Test("dismissing every suggestion empties the card and the dot")
    func dismissingClearsIt() async throws {
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

        let state = try await watching(p)
        #expect(state.suggestionLine?.hasPrefix("Aardvark") == true, "\(state.suggestionLine ?? "nil")")
    }
}
