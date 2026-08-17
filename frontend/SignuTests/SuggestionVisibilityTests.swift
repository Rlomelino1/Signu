import Testing
import Foundation
@testable import Signu

// Home counted a suggestion that Review refused to show (v64).
//
// Found in production the day R4 was wired: Home said "1 Possible subscriptions
// detected → Review", the Subs tab listed it under "SUGGESTED · 1", and tapping
// through to Review said **"You're all caught up"**. Nothing was broken about the
// data — the run existed, `possible`, unignored, with its charge.
//
// `makeReviewPayload` required a `nextExpectedDate` inside a `compactMap`:
//
//     guard let sub = …, let last = …, let next = run.nextExpectedDate else { return nil }
//
// An ENDED run has no expected date, and R4 can create one from a single old charge.
// Home's `suggestionCount` and the Subs row had no such requirement, so the three
// surfaces disagreed and the only one that could act on the suggestion was the one
// that hid it. A silent `nil` in a `compactMap` is invisible at the call site, which
// is why this reads as "the app is fine" from every angle except the user's.
//
// The rule these tests pin: **whatever Home counts, Review must render.**

@Suite("Suggestion visibility (v64)")
@MainActor
struct SuggestionVisibilityTests {

    private struct StubSource: SignuPayloadSource {
        var today = Date(timeIntervalSince1970: 1_787_000_000)   // 2026-08-17
        var now = Date(timeIntervalSince1970: 1_787_000_000)
        var profileValue: Profile! = Profile(
            id: UUID(), displayName: "Rafael", email: "r@example.test",
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

    /// Production's shape: one Claude charge from March, a `possible` R4 run whose
    /// lifecycle has already ended, so `nextExpectedDate` is nil.
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
                brand: "MASTERCARD", last4: "2049", officialName: "platinum",
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
                startDate: Date(timeIntervalSince1970: 1_772_668_800),   // 2026-03-05
                endDate: nextExpected == nil ? Date(timeIntervalSince1970: 1_775_347_200) : nil,
                cancelledDate: nil, billingInterval: .monthly, status: .possible,
                detectedBy: .r4, nextExpectedDate: nextExpected
            )
        ]
        s.chargeList = [
            Charge(
                id: UUID(), runId: runId, transactionId: txId,
                date: Date(timeIntervalSince1970: 1_772_668_800), amount: 20.97,
                currency: "USD", cardLabel: "Master 2049"
            )
        ]
        s.transactionAccountMap = [txId: accountId]
        return s
    }

    @Test("a suggestion with no predicted renewal still reaches Review")
    func datelessSuggestionIsRendered() {
        // THE regression. Before v64 this list was empty and the screen read
        // "You're all caught up" while Home advertised one suggestion.
        let review = Self.source(nextExpected: nil).makeReviewPayload()
        #expect(review.suggestions.count == 1)
        #expect(review.suggestions[0].serviceName == "Claude.Ai Subscription")
        #expect(review.suggestions[0].renewsDate == nil)
        // R4 still asks monthly-or-annual on Track it: the interval is unmeasured
        // whether or not a renewal is predictable.
        #expect(review.suggestions[0].asksIntervalOnTrack)
    }

    @Test("whatever Home counts, Review renders")
    func surfacesAgree() {
        // The invariant, stated as a comparison rather than as two numbers that
        // happen to match today. Checked in both shapes: with a prediction and
        // without one.
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
        // The other direction of the same invariant: agreement must not be achieved
        // by showing MORE than the user asked for.
        let review = Self.source(nextExpected: nil, ignored: true).makeReviewPayload()
        #expect(review.suggestions.isEmpty)
    }

    @Test("a run with no charge is still refused, and that is not the same bug")
    func chargelessRunIsNotRendered() {
        // Suggestions are decided on evidence (9a's rule: every confirm/dismiss is
        // made with the charges visible). A run with no charge has nothing to show,
        // so refusing it is correct rather than a silent drop -- and it cannot
        // happen for R3 or R4, which need 3 and 1 charges respectively.
        var source = Self.source(nextExpected: nil)
        source.chargeList = []
        #expect(source.makeReviewPayload().suggestions.isEmpty)
    }
}
