import Testing
import Foundation
@testable import Signu


@Suite("Suggestion visibility (v64)")
@MainActor
struct SuggestionVisibilityTests {

    private struct StubSource: SignuPayloadSource {
        var today = Date(timeIntervalSince1970: 1_787_000_000)
        var now = Date(timeIntervalSince1970: 1_787_000_000)
        var profileValue: Profile! = Profile(
            id: UUID(), displayName: "Alex", email: "r@example.test",
            providers: ["email"], avatarPath: nil,
            createdAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
        var connectionList: [Connection] = []
        var accountList: [BankAccount] = []
        var subscriptionList: [Subscription] = []
        var runList: [SubscriptionRun] = []
        var chargeList: [Charge] = []
        var transactionAccountMap: [UUID: UUID] = [:]
    }

    private static func source(nextExpected: Date?, ignored: Bool = false) -> StubSource {
        let subId = UUID(), runId = UUID(), txId = UUID(), accountId = UUID()
        var s = StubSource()
        s.connectionList = [
            Connection(
                id: UUID(), institutionId: "200", institutionName: "MeuPluggy",
                status: .active, consentExpiresAt: nil, lastSyncedAt: s.now,
                lastSyncError: nil, createdAt: Date(timeIntervalSince1970: 1_770_000_000)
            )
        ]
        s.accountList = [
            BankAccount(
                id: accountId, connectionId: s.connectionList[0].id, type: .creditCard,
                brand: "MASTERCARD", last4: "4321", officialName: "platinum",
                nickname: nil, status: .active
            )
        ]
        s.subscriptionList = [
            Subscription(
                id: subId, serviceName: "Claude.Ai Subscription", nickname: nil,
                merchantKey: "CLAUDE.AI SUBSCRIPTION", category: nil,
                identification: .auto, ignored: ignored, remindBeforeDays: nil,
                createdAt: Date(timeIntervalSince1970: 1_772_668_800)
            )
        ]
        s.runList = [
            SubscriptionRun(
                id: runId, subscriptionId: subId,
                startDate: Date(timeIntervalSince1970: 1_772_668_800),
                endDate: nextExpected == nil ? Date(timeIntervalSince1970: 1_775_347_200) : nil,
                cancelledDate: nil, billingInterval: .monthly, status: .possible,
                detectedBy: .r4, nextExpectedDate: nextExpected
            )
        ]
        s.chargeList = [
            Charge(
                id: UUID(), runId: runId, transactionId: txId,
                date: Date(timeIntervalSince1970: 1_772_668_800), amount: 20.97,
                currency: "USD", cardLabel: "Master 4321"
            )
        ]
        s.transactionAccountMap = [txId: accountId]
        return s
    }

    @Test("a suggestion with no predicted renewal still reaches Review")
    func datelessSuggestionIsRendered() {
        let review = Self.source(nextExpected: nil).makeReviewPayload()
        #expect(review.suggestions.count == 1)
        #expect(review.suggestions[0].serviceName == "Claude.Ai Subscription")
        #expect(review.suggestions[0].renewsDate == nil)
        #expect(review.suggestions[0].asksIntervalOnTrack)
    }

    @Test("whatever Home counts, Review renders")
    func surfacesAgree() {
        for next in [nil, Date(timeIntervalSince1970: 1_787_500_000)] {
            let source = Self.source(nextExpected: next)
            let home = source.makeHomePayload()
            let review = source.makeReviewPayload()
            let counted: Int
            switch home.content {
            case .watching(let w): counted = w.suggestionCount
            case .active(let a): counted = a.suggestionCount
            case .noBank: counted = 0
            }
            #expect(
                counted == review.suggestions.count,
                "Home counted \(counted), Review rendered \(review.suggestions.count)"
            )
        }
    }

    @Test("a dismissed suggestion is counted by nobody")
    func ignoredIsHiddenEverywhere() {
        let review = Self.source(nextExpected: nil, ignored: true).makeReviewPayload()
        #expect(review.suggestions.isEmpty)
    }

    @Test("a run with no charge is still refused, and that is not the same bug")
    func chargelessRunIsNotRendered() {
        var source = Self.source(nextExpected: nil)
        source.chargeList = []
        #expect(source.makeReviewPayload().suggestions.isEmpty)
    }
}
