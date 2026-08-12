import Testing
import Foundation
@testable import Signu

// The four writes the client is not granted (v30): confirming a suggestion,
// marking a run cancelled, removing a bank link, deleting an account. Each lives
// behind an Edge Function because Migration #1's grants refuse it from the app —
// `subscription_run` has no UPDATE grant at all and `authenticated` has no DELETE
// anywhere.
//
// Exercised through `MockDataProvider`, which simulates what each function does
// rather than no-opping, so these are real round trips: act, then read the payload
// the screen would render. The decisions themselves — which are the interesting
// part — are tested on the server side in _shared/actions.test.ts, against the
// same rules; these assert that the app asks for the right thing and shows the
// result.

@Suite("Server actions")
@MainActor
struct ServerActionsTests {

    private func provider() -> MockDataProvider { MockDataProvider() }

    /// The R3 suggestion (ChatGPT Plus): cadence measured, so no interval sheet.
    private func r3Suggestion(_ p: MockDataProvider) async throws -> ReviewPayload.Suggestion {
        let suggestions = try await p.reviewPayload().suggestions
        return try #require(suggestions.first { !$0.asksIntervalOnTrack })
    }

    /// The R4 suggestion (Meli+): one charge, so the sheet asks monthly/annual.
    private func r4Suggestion(_ p: MockDataProvider) async throws -> ReviewPayload.Suggestion {
        let suggestions = try await p.reviewPayload().suggestions
        return try #require(suggestions.first { $0.asksIntervalOnTrack })
    }

    // MARK: - Track it

    @Test("confirming a suggestion tracks it and takes it out of review")
    func confirmTracks() async throws {
        let p = provider()
        let suggestion = try await r3Suggestion(p)
        let before = try await p.reviewPayload().suggestions.count

        try await p.confirmSuggestion(runId: suggestion.id, billingInterval: nil)

        let after = try await p.reviewPayload()
        #expect(after.suggestions.count == before - 1)
        #expect(!after.suggestions.contains { $0.id == suggestion.id })

        let run = try #require(try await p.runs(subscriptionId: suggestion.subscriptionId).first)
        #expect(run.status == .active)
        let sub = try #require(try await p.subscriptions().first { $0.id == suggestion.subscriptionId })
        #expect(sub.identification == .userConfirmed)
    }

    @Test("a confirmed suggestion becomes a real subscription with a detail screen")
    func confirmEarnsADetailScreen() async throws {
        // "Confirmation is the moment a subscription earns a detail screen" —
        // possible runs live on 9a only, so this is the observable difference.
        let p = provider()
        let suggestion = try await r3Suggestion(p)

        try await p.confirmSuggestion(runId: suggestion.id, billingInterval: nil)

        let detail = try #require(try await p.detailPayload(subscriptionId: suggestion.subscriptionId))
        #expect(detail.showMarkCancelled)
    }

    @Test("an R4 confirmation writes the interval the user chose")
    func r4IntervalIsAuthoritative() async throws {
        // R4 creates a run from a single charge and writes a provisional monthly.
        // The sheet's answer overwrites it — that is the authoritative write.
        let p = provider()
        let suggestion = try await r4Suggestion(p)

        try await p.confirmSuggestion(runId: suggestion.id, billingInterval: .annual)

        let run = try #require(try await p.runs(subscriptionId: suggestion.subscriptionId).first)
        #expect(run.billingInterval == .annual)
        #expect(run.status == .active)
    }

    @Test("confirming a renamed subscription leaves identification alone")
    func renameSurvivesConfirmation() async throws {
        // `user_renamed` freezes service_name against the engine. Demoting it to
        // `user_confirmed` would unfreeze the name and let the next detection
        // pass overwrite what the user typed.
        let p = provider()
        let suggestion = try await r3Suggestion(p)
        let i = try #require(p.subscriptionList.firstIndex { $0.id == suggestion.subscriptionId })
        p.subscriptionList[i].identification = .userRenamed

        try await p.confirmSuggestion(runId: suggestion.id, billingInterval: nil)

        let sub = try #require(try await p.subscriptions().first { $0.id == suggestion.subscriptionId })
        #expect(sub.identification == .userRenamed)
        // The run still moved — the weaker assertion is what was declined, not the
        // confirmation itself.
        let run = try #require(try await p.runs(subscriptionId: sub.id).first)
        #expect(run.status == .active)
    }

    // MARK: - Mark cancelled

    /// The newest run of a subscription — the one every screen reasons about,
    /// and the one the Edge Function resolves for itself.
    private func latestRun(_ p: MockDataProvider, _ subscriptionId: UUID) async throws -> SubscriptionRun? {
        try await p.runs(subscriptionId: subscriptionId).max { $0.startDate < $1.startDate }
    }

    private func subscription(_ p: MockDataProvider, withLatestRun status: RunStatus) async throws -> Subscription? {
        for sub in try await p.subscriptions() where try await latestRun(p, sub.id)?.status == status {
            return sub
        }
        return nil
    }

    @Test("cancelling ends the run and stops the renewal")
    func cancelEndsTheRun() async throws {
        let p = provider()
        let sub = try #require(try await subscription(p, withLatestRun: .active))
        let runBefore = try #require(try await latestRun(p, sub.id))
        let lastCharge = try #require(try await p.charges(runId: runBefore.id).map(\.date).max())

        try await p.markCancelled(subscriptionId: sub.id)

        let run = try #require(try await p.runs(subscriptionId: sub.id).first { $0.id == runBefore.id })
        #expect(run.status == .cancelled)
        #expect(run.cancelledDate == p.today)
        // end_date is paid-through — one interval past the last charge, NOT the
        // day the user got round to telling us.
        let expected = SignuCalendar.saoPaulo.date(
            byAdding: .month,
            value: run.billingInterval == .annual ? 12 : 1,
            to: lastCharge
        )
        #expect(run.endDate == expected)
        // Never in "Coming up" again, and it can never trip overdue.
        #expect(run.nextExpectedDate == nil)
    }

    @Test("cancelling an already-dead run does nothing")
    func cancelIsRefusedOnDeadRuns() async throws {
        // The button only renders on active and overdue runs. If it ever reached
        // an ended one, overwriting the engine's inference with an assertion the
        // data does not support would be a downgrade.
        let p = provider()
        let ended = try #require(try await subscription(p, withLatestRun: .ended))
        let before = try #require(try await latestRun(p, ended.id))

        try await p.markCancelled(subscriptionId: ended.id)

        let after = try #require(try await p.runs(subscriptionId: ended.id).first { $0.id == before.id })
        #expect(after.status == .ended)
        #expect(after.cancelledDate == nil)
        #expect(after.endDate == before.endDate)
    }

    // MARK: - Remove a bank link

    /// A connection with subscriptions attributed to it, plus that count.
    private func connectionWithSubs(_ p: MockDataProvider) async throws -> (id: UUID, count: Int)? {
        for connection in try await p.connections() {
            if let payload = try await p.attributedSubsPayload(connectionId: connection.id),
               payload.headerCount > 0 {
                return (connection.id, payload.headerCount)
            }
        }
        return nil
    }

    @Test("removing a link and keeping history leaves the subscriptions standing")
    func removeKeepingHistory() async throws {
        let p = provider()
        let (connectionId, attributed) = try #require(try await connectionWithSubs(p))
        let subsBefore = try await p.subscriptions().count

        try await p.removeConnection(connectionId: connectionId, deleteHistory: false)

        #expect(!(try await p.connections().contains { $0.id == connectionId }))
        #expect(try await p.subscriptions().count == subsBefore)
        #expect(attributed > 0)
        // The charges survive the loss of their transactions, self-described by
        // the duplicated date, amount and card label. That is what "they just
        // stop updating from this bank" means.
        var surviving: [Charge] = []
        for sub in try await p.subscriptions() {
            for run in try await p.runs(subscriptionId: sub.id) {
                surviving += try await p.charges(runId: run.id)
            }
        }
        #expect(surviving.contains { $0.transactionId == nil })
        #expect(surviving.allSatisfy { !$0.cardLabel.isEmpty })
    }

    @Test("removing a link with history takes exactly the attributed subscriptions")
    func removeDeletingHistory() async throws {
        // The count in the sheet and the count deleted are the same number by
        // construction: both come from the attribution rule, computed once.
        let p = provider()
        let (connectionId, attributed) = try #require(try await connectionWithSubs(p))
        let subsBefore = try await p.subscriptions().count

        try await p.removeConnection(connectionId: connectionId, deleteHistory: true)

        #expect(!(try await p.connections().contains { $0.id == connectionId }))
        #expect(try await p.subscriptions().count == subsBefore - attributed)
    }

    @Test("the attributed count includes dismissed subscriptions")
    func attributionCountsDismissed() async throws {
        // Dismissed suggestions have charges too; "Delete them too" takes their
        // data with it, and silently keeping ghost data the user cannot see would
        // be the worst available outcome.
        let p = provider()
        let (connectionId, attributed) = try #require(try await connectionWithSubs(p))
        let payload = try #require(try await p.attributedSubsPayload(connectionId: connectionId))
        let visible = payload.cardGroups.reduce(0) { $0 + $1.rows.count }
        #expect(visible + payload.dismissed.count == attributed)
    }

    // MARK: - Connecting a bank

    @Test("a connect session is minted before the widget runs")
    func connectSessionIsMinted() async throws {
        // The mock has no widget, and says so rather than handing back a token
        // that would load a web view into a failure.
        let p = provider()
        let session = try await p.connectSession(connectionId: nil)
        #expect(!session.accessToken.isEmpty)
        #expect(session.simulated)
    }

    @Test("registering an item adds the bank and its card")
    func registerAddsTheBank() async throws {
        let p = provider()
        let banksBefore = try await p.connections().count

        try await p.registerConnection(itemId: "item-1")

        #expect(try await p.connections().count == banksBefore + 1)
        let settings = try await p.settingsPayload()
        #expect(settings.banks.contains { $0.name == "Simulated Bank" })
        // A connection with no accounts renders a bank row that claims 0 cards,
        // so the fixture adds one — the real path gets its accounts from the
        // sync that `register-connection` chains into.
        let connection = try #require(try await p.connections().first { $0.institutionName == "Simulated Bank" })
        #expect(try await p.bankAccounts().contains { $0.connectionId == connection.id })
    }

    @Test("registering the same item twice does not duplicate the bank")
    func registerIsIdempotent() async throws {
        // UNIQUE (user_id, provider_connection_id) is what makes this true on the
        // real path; a double tap or a retried request must not produce two links.
        let p = provider()
        try await p.registerConnection(itemId: "item-1")
        let after = try await p.connections().count
        try await p.registerConnection(itemId: "item-1")
        #expect(try await p.connections().count == after)
    }

    // MARK: - Delete account

    @Test("deleting the account takes everything the cascade would")
    func deleteAccountWipes() async throws {
        let p = provider()
        #expect(try await p.subscriptions().count > 0)

        try await p.deleteAccount()

        #expect(try await p.connections().isEmpty)
        #expect(try await p.bankAccounts().isEmpty)
        #expect(try await p.subscriptions().isEmpty)
        let settings = try await p.settingsPayload()
        #expect(settings.banks.isEmpty)
        #expect(settings.dismissed.isEmpty)
    }
}
