import Testing
import Foundation
@testable import Signu


@Suite("Gate: session ended")
@MainActor
struct GateSessionEndTests {

    private final class Provider: SessionProviding {
        var currentEmail: String?
        private var continuation: AsyncStream<Void>.Continuation?
        var restoreState: AuthGateState = .authenticated

        func end() { continuation?.yield(()) }

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

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func store(in state: AuthGateState) async -> (SessionStore, Provider) {
        let provider = Provider()
        provider.restoreState = state
        provider.currentEmail = "someone@example.test"
        let store = SessionStore(provider: provider)
        await store.restore()
        #expect(store.gateState == state)
        await waitUntil { provider.isObserved }
        return (store, provider)
    }

    @Test("a session ending signs the user out of the shell")
    func fromAuthenticated() async throws {
        let (store, provider) = await store(in: .authenticated)
        provider.end()
        await waitUntil { store.gateState == .unauthenticated }
        #expect(store.gateState == .unauthenticated)
        #expect(store.email == nil)
    }

    @Test("a session ending during recovery returns to the welcome flow")
    func fromRecovering() async throws {
        let (store, provider) = await store(in: .recovering)
        provider.end()
        await waitUntil { store.gateState == .unauthenticated }
        #expect(store.gateState == .unauthenticated)
    }

    @Test("it does not claim the recovery link expired")
    func recoveryNoticeIsNotFabricated() async throws {
        let (store, provider) = await store(in: .recovering)
        provider.end()
        await waitUntil { store.gateState == .unauthenticated }
        #expect(store.expiredRecoveryLink == false)
    }

    @Test("already unauthenticated is untouched")
    func fromUnauthenticated() async throws {
        let (store, provider) = await store(in: .unauthenticated)
        provider.end()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.gateState == .unauthenticated)
    }

    @Test("the watcher starts only after restore has resolved")
    func doesNotRaceRestore() async throws {
        let provider = Provider()
        provider.restoreState = .authenticated
        let store = SessionStore(provider: provider)
        provider.end()
        await store.restore()
        #expect(store.gateState == .authenticated)

        await waitUntil { provider.isObserved }
        provider.end()
        await waitUntil { store.gateState == .unauthenticated }
        #expect(store.gateState == .unauthenticated)
    }
}
