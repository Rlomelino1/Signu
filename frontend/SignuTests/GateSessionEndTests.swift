import Testing
import Foundation
@testable import Signu

// What the gate does when a session ends without the app asking (v41).
//
// The defect this closes: `SessionStore` flipped to `.authenticated` on a
// successful sign-in and then nothing observed auth state. A session that
// disappeared — a refresh that failed, a revoked token — left a signed-in shell
// over a signed-out client. Every read went out with the anon key, `anon` was
// revoked everything by Migration #1, and the user was told "permission denied
// for table profiles" on a blank screen with a working tab bar. The auth failure
// presented itself as a database permissions bug.
//
// One test per cell of the (state, event) pair, because that is how the funnel is
// written and a cell that does nothing has to be a decision rather than an
// omission.

@Suite("Gate: session ended")
@MainActor
struct GateSessionEndTests {

    /// Drives the gate directly: a session that ends on command, and nothing else.
    private final class Provider: SessionProviding {
        var currentEmail: String?
        private var continuation: AsyncStream<Void>.Continuation?
        var restoreState: AuthGateState = .authenticated

        func end() { continuation?.yield(()) }

        /// Whether anyone is actually listening yet. The stream's closure runs
        /// when `sessionEndings()` is called, which happens inside the store's
        /// observer task — so "restore returned" does not mean "the observer is
        /// attached", and a yield before it is gets dropped on the floor.
        var isObserved: Bool { continuation != nil }

        func sessionEndings() -> AsyncStream<Void> {
            AsyncStream { continuation in self.continuation = continuation }
        }

        func restore() async -> AuthGateState { restoreState }
        func signIn(email: String, password: String) async throws { currentEmail = email }
        func signUp(name: String, email: String, password: String) async throws {}
        func signInWithGoogle() async throws {}
        func resendConfirmation(email: String) async throws {}
        func checkConfirmation() async throws -> Bool { true }
        func requestPasswordReset(email: String) async throws {}
        func updatePassword(_ password: String) async throws {}
        func signOut() async { currentEmail = nil }
        func handleAuthCallback(_ url: URL) async -> AuthCallbackOutcome? { nil }
    }

    /// Waits for the observer task to deliver, rather than assuming one
    /// `Task.yield()` is enough — it is not, and a single yield made two of these
    /// tests pass vacuously while the other two failed for the same reason.
    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Restores into a known state with the watcher running.
    private func store(in state: AuthGateState) async -> (SessionStore, Provider) {
        let provider = Provider()
        provider.restoreState = state
        provider.currentEmail = "someone@example.com"
        let store = SessionStore(provider: provider)
        await store.restore()
        #expect(store.gateState == state)
        await waitUntil { provider.isObserved }
        return (store, provider)
    }

    @Test("a session ending signs the user out of the shell")
    func fromAuthenticated() async throws {
        // THE fix. Anything else here is a blank screen with a tab bar.
        let (store, provider) = await store(in: .authenticated)
        provider.end()
        await waitUntil { store.gateState == .unauthenticated }
        #expect(store.gateState == .unauthenticated)
        #expect(store.email == nil)
    }

    @Test("a session ending during recovery returns to the welcome flow")
    func fromRecovering() async throws {
        // 17e submits against the recovery session, so without one the form is
        // guaranteed to fail. Leaving it on screen would be the dishonest option.
        let (store, provider) = await store(in: .recovering)
        provider.end()
        await waitUntil { store.gateState == .unauthenticated }
        #expect(store.gateState == .unauthenticated)
    }

    @Test("it does not claim the recovery link expired")
    func recoveryNoticeIsNotFabricated() async throws {
        // 17d renders a "request a new one" notice from that flag. A session that
        // died is not evidence the link expired, and the screen may not say it was.
        let (store, provider) = await store(in: .recovering)
        provider.end()
        await waitUntil { store.gateState == .unauthenticated }
        #expect(store.expiredRecoveryLink == false)
    }

    @Test("already unauthenticated is untouched")
    func fromUnauthenticated() async throws {
        // Voluntary sign-out reaches this event too — the SDK reports both the
        // same way — so it has to be harmless rather than exceptional.
        let (store, provider) = await store(in: .unauthenticated)
        provider.end()
        // Nothing to wait FOR, so this waits a beat and asserts nothing moved.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.gateState == .unauthenticated)
    }

    @Test("the watcher starts only after restore has resolved")
    func doesNotRaceRestore() async throws {
        // The load-bearing cell. An event acted on during `.restoring` is the
        // late-restore race the funnel was built to prevent, so the watcher is
        // started after restore and `.restoring` ignores the event regardless.
        let provider = Provider()
        provider.restoreState = .authenticated
        let store = SessionStore(provider: provider)
        provider.end()                    // before restore: nobody is listening yet
        await store.restore()
        #expect(store.gateState == .authenticated)

        await waitUntil { provider.isObserved }
        provider.end()                    // now observed: honoured
        await waitUntil { store.gateState == .unauthenticated }
        #expect(store.gateState == .unauthenticated)
    }
}
