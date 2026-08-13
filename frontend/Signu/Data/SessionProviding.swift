import Foundation

/// Where the app sits in the auth gate — the single value `RootView`
/// switches on. Four states, and deliberately no "signed in but unverified"
/// branch: email confirmation is ON and non-negotiable (auth flow contract),
/// so a session existing *implies* the email is verified. 17b → 17c is
/// navigation inside `WelcomeFlow`, never a gate transition.
enum AuthGateState: Equatable {
    /// Cold launch, session restore in flight. Renders `SplashView`.
    /// Exists to prevent the launch flash — without it a signed-in user sees
    /// 16a for ~200ms on every launch.
    case restoring
    /// No session. Renders `WelcomeFlow` from its 16a root.
    case unauthenticated
    /// A live session produced by a password-reset deep link, *before* the
    /// new password is set. Renders 17e standalone. See `SessionStore` for
    /// why this can never be folded into `.authenticated`.
    case recovering
    /// Renders `AppShellView`.
    case authenticated
}

/// Auth actions boundary, mirroring `SignuDataProviding`: one call per
/// affordance the locked screens (16a, 17a–17e) actually offer, nothing
/// speculative. A Supabase-backed provider slots in behind this protocol
/// without touching views — the gate above it never learns what a token is.
///
/// `@MainActor`, mirroring `SignuDataProviding` for the same reason. `SessionStore`
/// is main-actor and holds one of these; awaiting a *nonisolated* method on it
/// sends the instance across an actor boundary, which Swift 6 rejects. The
/// underlying SDK calls suspend and do their work wherever they like — the
/// isolation is on who may call them, not on where the network happens.
@MainActor
protocol SessionProviding {
    /// Cold-launch restore: the gate state the app should open in. Called
    /// once, while `SplashView` is on screen.
    func restore() async -> AuthGateState

    /// 17a.
    func signIn(email: String, password: String) async throws
    /// 17b. Returns Void deliberately: confirmation is ON, so signup never
    /// yields a session and 17b always pushes to 17c. There is no
    /// "maybe signed in" outcome to report.
    func signUp(name: String, email: String, password: String) async throws
    /// 16a. Google sign-ins never require confirmation — Google verified the
    /// address, so this lands straight in `.authenticated`.
    func signInWithGoogle() async throws
    /// 17c's resend, and the resend action of 17a's unverified variant.
    func resendConfirmation(email: String) async throws
    /// 17c's manual "I've confirmed my email" — the wrong-device path, where
    /// the deep link fired on a laptop or nowhere. `getUser()` in the real
    /// provider; true = `email_confirmed_at` is set.
    func checkConfirmation() async throws -> Bool
    /// 17d. Succeeds unconditionally by contract (enumeration-safe), so the
    /// screen may never claim a send happened.
    func requestPasswordReset(email: String) async throws
    /// 17e. Runs against the live recovery session; its success is the only
    /// thing that ends `.recovering`.
    func updatePassword(_ password: String) async throws
    func signOut() async

    /// Resolves an auth-callback deep link. Real provider: hand the URL to
    /// the SDK, which exchanges the tokens and reports what came back. Mock:
    /// read the designated query param. nil = not an auth callback we know.
    func handleAuthCallback(_ url: URL) async -> AuthCallbackOutcome?

    /// Address of the current session — 17e renders it ("You're signed in
    /// as …"), which doubles as a right-account check.
    var currentEmail: String? { get }

    /// Sessions that end without the app asking: a token refresh that failed, a
    /// token revoked server-side, storage cleared underneath us.
    ///
    /// This exists because the gate had no way to hear about one. It flipped to
    /// `.authenticated` when sign-in succeeded and then never looked again, so a
    /// session that disappeared left a **signed-in shell over a signed-out
    /// client**: every read went out with the anon key, and since `anon` was
    /// revoked everything by Migration #1, the user got "permission denied for
    /// table profiles" on a blank screen with a working tab bar. Four steps
    /// between the real problem and the message — the auth failure presented
    /// itself as a database permissions bug.
    ///
    /// Called once, at launch. Voluntary sign-out may also arrive here; the gate
    /// is written so that is harmless, since both end in the same state.
    func sessionEndings() -> AsyncStream<Void>
}

/// What an auth-callback deep link produced. The three real outcomes of the
/// one mechanism the confirm and reset flows share.
enum AuthCallbackOutcome: Equatable {
    /// Confirmation link: a session arrived. **The session arriving IS the
    /// signal** (auth flow contract) — no polling, no status check.
    case authenticated
    /// Recovery link: tokens exchanged, session live, password still the old
    /// one. Must land on 17e, never Home.
    case recovering(email: String?)
    /// Reset links expire (~1h). Routes back to 17d with a notice rather
    /// than dead-ending silently.
    case expiredRecoveryLink
}

/// Auth failures the locked screens distinguish. Deliberately short:
/// Supabase's enumeration-safe posture refuses to say whether an account
/// exists or how it signs in, so neither may this.
enum SessionAuthError: Error, Equatable {
    /// 17a's generic failure — generic by necessity, not by omission.
    case invalidCredentials
    /// Supabase returns a *distinct* "email not confirmed" error. A different
    /// screen state from `invalidCredentials`, with its own copy and a resend
    /// action. Covers the user who abandoned 17c and came back days later.
    case emailNotConfirmed
    /// Resend tapped inside the 120s cooldown (Supabase's ~60s email rate
    /// limit). The cooldown UI exists so this is normally unreachable.
    case rateLimited
}

extension SessionAuthError {
    /// Copy for 17a's two failure variants.
    ///
    /// `invalidCredentials` is quoted verbatim from the auth flow contract —
    /// it signposts both exits from the Google-first-user trap.
    ///
    /// `emailNotConfirmed` has **no locked string**: the contract specifies
    /// "verify-specific copy with a resend action" without writing either.
    /// The string below is a placeholder, and 17a has no error slot to render
    /// it in — both gaps are reported in the PR rather than designed here.
    var signInMessage: String {
        switch self {
        case .invalidCredentials:
            "Couldn't sign in. Check your password — if you signed up with Google you need to set a password first by tapping on Forgot password, or go back and continue with Google."
        case .emailNotConfirmed:
            "Your email isn't confirmed yet."     // NOT locked copy — see above
        case .rateLimited:
            "Too many attempts. Try again in a moment."
        }
    }
}
