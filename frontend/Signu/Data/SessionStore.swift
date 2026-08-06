import Foundation

/// Owns `gateState` — the one value `RootView` switches on — and delegates
/// every action to a `SessionProviding`. Same idiom as `TabBarState`:
/// `@Observable`, handed down from the app root, with the mock/real swap
/// happening below it (the store never learns which provider it holds).
@MainActor
@Observable
final class SessionStore {
    private(set) var gateState: AuthGateState = .restoring

    /// Address of the current session. 17e renders it; 17c's resend needs it.
    private(set) var email: String?

    /// Last auth failure, for the screens that render one.
    private(set) var lastError: SessionAuthError?

    /// A recovery deep link that had expired. 17d consumes this to render the
    /// "request a new one" notice instead of dead-ending (auth flow contract).
    private(set) var expiredRecoveryLink = false

    @ObservationIgnored private let provider: SessionProviding

    init(provider: SessionProviding) {
        self.provider = provider
    }

    // MARK: - Cold launch

    /// Resolves `.restoring` into a real state. Runs while `SplashView` is on
    /// screen; the splash is what keeps a signed-in user from seeing 16a flash
    /// past on every launch.
    func restore() async {
        let restored = await provider.restore()
        // A deep link can land while restore is still in flight — a cold
        // launch from an email link is exactly that race. Whatever the link
        // decided wins: without this guard a late restore overwrites
        // `.recovering` with `.authenticated` and drops the user on Home with
        // their password unchanged, which is the very bug `.recovering` exists
        // to prevent.
        guard gateState == .restoring else { return }
        email = provider.currentEmail
        gateState = restored
    }

    // MARK: - Actions

    /// 17a.
    func signIn(email address: String, password: String) async {
        lastError = nil
        do {
            try await provider.signIn(email: address, password: password)
            email = provider.currentEmail ?? address
            gateState = .authenticated
        } catch {
            lastError = authError(error)
        }
    }

    /// 17b. Deliberately does not move the gate: confirmation is ON, so
    /// signup yields no session and `WelcomeFlow` pushes to 17c. Returns
    /// whether the signup itself succeeded, so the caller knows whether to
    /// push — not whether a session exists (it never does).
    @discardableResult
    func signUp(name: String, email address: String, password: String) async -> Bool {
        lastError = nil
        do {
            try await provider.signUp(name: name, email: address, password: password)
            email = address
            return true
        } catch {
            lastError = authError(error)
            return false
        }
    }

    /// 16a. Google verified the address, so this lands in `.authenticated`
    /// with no confirmation interstitial.
    func signInWithGoogle() async {
        lastError = nil
        do {
            try await provider.signInWithGoogle()
            email = provider.currentEmail
            gateState = .authenticated
        } catch {
            lastError = authError(error)
        }
    }

    /// 17c's resend, and 17a's unverified-variant resend.
    func resendConfirmation(email address: String) async {
        lastError = nil
        do {
            try await provider.resendConfirmation(email: address)
        } catch {
            lastError = authError(error)
        }
    }

    /// 17c's "I've confirmed my email" — the wrong-device path. true means
    /// the gate has already moved to `.authenticated`; false leaves 17c to
    /// render its inline "Not confirmed yet" line.
    func checkConfirmation() async -> Bool {
        lastError = nil
        do {
            guard try await provider.checkConfirmation() else { return false }
            email = provider.currentEmail ?? email
            gateState = .authenticated
            return true
        } catch {
            lastError = authError(error)
            return false
        }
    }

    /// 17d. Unconditional success by contract — the caller must not read a
    /// return value as evidence a send happened.
    func requestPasswordReset(email address: String) async {
        lastError = nil
        do {
            try await provider.requestPasswordReset(email: address)
        } catch {
            lastError = authError(error)
        }
    }

    /// 17e's submit — and the **only** exit from `.recovering`.
    ///
    /// Why `.recovering` exists at all: the reset deep link exchanges tokens
    /// and produces a LIVE SESSION *before* the new password is set. A gate
    /// written as `if session != nil { shell }` therefore swallows 17e
    /// entirely — the user taps the email link and lands on Home with the
    /// password unchanged. The store holds `.recovering` from the recovery
    /// event until this call succeeds, and only then flips to
    /// `.authenticated`. Do not collapse the two states in a later refactor.
    func updatePassword(_ password: String) async {
        lastError = nil
        do {
            try await provider.updatePassword(password)
            email = provider.currentEmail ?? email
            gateState = .authenticated
        } catch {
            lastError = authError(error)
        }
    }

    /// Both exits (12a sign-out — see the PR note — and 14a's delete
    /// confirmation) land here. Returning to `WelcomeFlow` is free: the gate
    /// reacts to the state, so neither exit routes anywhere explicitly.
    func signOut() async {
        await provider.signOut()
        email = nil
        lastError = nil
        expiredRecoveryLink = false
        gateState = .unauthenticated
    }

    // MARK: - Deep links

    static let urlScheme = "signu"
    static let authCallbackHost = "auth-callback"

    /// Handles `signu://auth-callback…`. Attached at the app root, above the
    /// gate — links fire in both unauthenticated (confirm, recovery) and
    /// authenticated states, so no screen inside `WelcomeFlow` can own this.
    func handle(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme,
              url.host?.lowercased() == Self.authCallbackHost
        else { return }

        Task {
            guard let outcome = await provider.handleAuthCallback(url) else { return }
            switch outcome {
            case .authenticated:
                // 17c's exit: the session arriving IS the signal.
                email = provider.currentEmail ?? email
                expiredRecoveryLink = false
                gateState = .authenticated
            case .recovering(let address):
                // Must land on 17e, not Home — see updatePassword() above.
                email = address ?? provider.currentEmail ?? email
                expiredRecoveryLink = false
                gateState = .recovering
            case .expiredRecoveryLink:
                // Back to 17d with the notice, never a silent dead end.
                expiredRecoveryLink = true
                gateState = .unauthenticated
            }
        }
    }

    /// Called by 17d once it has rendered the expired-link notice, so a later
    /// visit to the screen doesn't show a stale warning.
    func consumeExpiredRecoveryLink() {
        expiredRecoveryLink = false
    }

    // MARK: - Bits

    private func authError(_ error: Error) -> SessionAuthError {
        error as? SessionAuthError ?? .invalidCredentials
    }
}

#if DEBUG
extension SessionStore {
    /// `--link=confirm|recovery|expired`: fires the corresponding mock deep
    /// link through the real `handle(url:)` path, so the harness exercises
    /// the same code `simctl openurl` does.
    func fireLaunchLinkIfRequested() {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--link=") }) else { return }
        let name = String(arg.dropFirst("--link=".count))
        guard let url = URL(string: "\(Self.urlScheme)://\(Self.authCallbackHost)?mock=\(name)") else { return }
        handle(url: url)
    }
}
#endif
