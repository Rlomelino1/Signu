import Foundation

/// Owns `gateState` — the one value `RootView` switches on — and delegates
/// every action to a `SessionProviding`. Same idiom as `TabBarState`:
/// `@Observable`, handed down from the app root, with the mock/real swap
/// happening below it (the store never learns which provider it holds).
@MainActor
@Observable
final class SessionStore {
    /// Sole writer: `apply(_:)`. Assigning it anywhere else is the defect —
    /// see the funnel's comment for why.
    private(set) var gateState: AuthGateState = .restoring

    /// Address of the current session. 17e renders it; 17c's resend needs it.
    private(set) var email: String?

    /// Last auth failure, for the screens that render one.
    private(set) var lastError: SessionAuthError?

    /// Drop a stale failure. `lastError` is global to the store, so without this
    /// a failed sign-in would still be on screen after tapping "Forgot password?"
    /// — the error belongs to the attempt, not to the session.
    func clearError() { lastError = nil }

    /// A recovery deep link that had expired. 17d consumes this to render the
    /// "request a new one" notice instead of dead-ending (auth flow contract).
    private(set) var expiredRecoveryLink = false

    @ObservationIgnored private let provider: SessionProviding

    init(provider: SessionProviding) {
        self.provider = provider
    }

    // MARK: - Transitions

    /// Everything that can move the gate. Not a mirror of the UI actions:
    /// several actions (17b's signup, 17d's request, both resends) move the
    /// gate nowhere, and three different actions raise `.signedIn`.
    enum GateEvent: Equatable {
        /// Cold-launch restore resolved.
        case restored(AuthGateState)
        /// A session arrived through the UI — 17a, 16a's Google button, or
        /// 17c's manual check.
        case signedIn(email: String?)
        /// Confirmation deep link. The session arriving **is** the signal.
        case confirmLink
        /// Recovery deep link: tokens exchanged, session live, password still
        /// the old one.
        case recoveryLink(email: String?)
        /// Recovery deep link that had already expired. "The link failed" is
        /// not the same fact as "there is no session" — the distinction the
        /// `.authenticated` and `.recovering` cells below turn on.
        case expiredRecoveryLink
        /// 17e's submit succeeded. The only exit from `.recovering`.
        case passwordUpdated
        /// 12a's sign-out, 14a's delete.
        case signedOut
    }

    /// The one place `gateState` is written.
    ///
    /// Every transition is a function of **(current state, event)**, never of
    /// the event alone. Blind assignment was the same defect twice — a late
    /// restore overwriting a link's decision, and an expired link ejecting a
    /// signed-in user — so it is funnelled here rather than patched per site.
    ///
    /// Each event lists all four states with no `default`, so the compiler
    /// forces a decision per cell and a `break` reads as one rather than as an
    /// omission.
    private func apply(_ event: GateEvent) {
        switch event {

        case .restored(let restored):
            switch gateState {
            case .restoring:
                email = provider.currentEmail
                // A stale link's notice belongs to 17d; if restore found a
                // session there is no 17d to render it on.
                if restored == .authenticated { expiredRecoveryLink = false }
                gateState = restored
            case .unauthenticated, .recovering, .authenticated:
                // A deep link can land while restore is still in flight — a
                // cold launch from an email link is exactly that race. The
                // link already decided, and it wins: a late restore
                // overwriting `.recovering` with `.authenticated` drops the
                // user on Home with their password unchanged, the very bug
                // `.recovering` exists to prevent.
                break
            }

        case .signedIn(let address):
            switch gateState {
            case .restoring, .unauthenticated:
                email = address ?? provider.currentEmail
                gateState = .authenticated
            case .recovering:
                // 17e has no back chevron, so no sign-in screen is reachable
                // from it — and the session there is already live. Accepting
                // this would skip the password change.
                break
            case .authenticated:
                break
            }

        case .confirmLink:
            switch gateState {
            case .restoring, .unauthenticated:
                email = provider.currentEmail ?? email
                expiredRecoveryLink = false
                gateState = .authenticated
            case .recovering:
                // 17e still owes a password. A confirmation link must not eat
                // it, for the same reason Home must not.
                break
            case .authenticated:
                break
            }

        case .recoveryLink(let address):
            switch gateState {
            case .restoring, .unauthenticated, .recovering, .authenticated:
                // The only event all four states agree on. `.authenticated`
                // included, deliberately: a signed-in user tapping a reset
                // link must land on 17e, never Home.
                email = address ?? provider.currentEmail ?? email
                expiredRecoveryLink = false
                gateState = .recovering
            }

        case .expiredRecoveryLink:
            switch gateState {
            case .unauthenticated:
                // 17d, with the notice — never a silent dead end.
                expiredRecoveryLink = true
            case .restoring:
                // Defer: whether a session exists is still unknown. Raise the
                // notice and let restore resolve the state; `WelcomeFlow`
                // reads the flag with `initial: true`, so a cold launch from a
                // stale link still lands on 17d.
                expiredRecoveryLink = true
            case .recovering, .authenticated:
                // A live session the failed link never invalidated. Nothing to
                // route to, and ejecting them would be a false sign-out.
                break
            }

        case .passwordUpdated:
            switch gateState {
            case .recovering:
                email = provider.currentEmail ?? email
                gateState = .authenticated
            case .restoring, .unauthenticated, .authenticated:
                // 17e is only on screen in `.recovering`.
                break
            }

        case .signedOut:
            switch gateState {
            case .restoring, .unauthenticated, .recovering, .authenticated:
                // Unconditional, including from `.recovering`: abandoning the
                // reset flow is a legitimate exit.
                email = nil
                lastError = nil
                expiredRecoveryLink = false
                gateState = .unauthenticated
            }
        }
    }

    // MARK: - Cold launch

    /// Resolves `.restoring` into a real state. Runs while `SplashView` is on
    /// screen; the splash is what keeps a signed-in user from seeing 16a flash
    /// past on every launch.
    func restore() async {
        apply(.restored(await provider.restore()))
    }

    // MARK: - Actions

    /// 17a.
    func signIn(email address: String, password: String) async {
        lastError = nil
        do {
            try await provider.signIn(email: address, password: password)
            apply(.signedIn(email: provider.currentEmail ?? address))
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
            apply(.signedIn(email: provider.currentEmail))
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
            apply(.signedIn(email: provider.currentEmail ?? email))
            // Reports whether the gate actually moved, not what the provider
            // said — the funnel is what decides.
            return gateState == .authenticated
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
            apply(.passwordUpdated)
        } catch {
            lastError = authError(error)
        }
    }

    /// Both exits (12a sign-out — see the PR note — and 14a's delete
    /// confirmation) land here. Returning to `WelcomeFlow` is free: the gate
    /// reacts to the state, so neither exit routes anywhere explicitly.
    func signOut() async {
        await provider.signOut()
        apply(.signedOut)
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
            // What the link produced; what it *means* for the gate is the
            // funnel's call, since that depends on where the user already is.
            switch outcome {
            case .authenticated:
                apply(.confirmLink)
            case .recovering(let address):
                apply(.recoveryLink(email: address))
            case .expiredRecoveryLink:
                apply(.expiredRecoveryLink)
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
