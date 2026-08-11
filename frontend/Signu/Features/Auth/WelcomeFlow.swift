import SwiftUI

/// The unauthenticated navigation stack: 16a → 17a–17d. Hosted by the gate's
/// `.unauthenticated` state, which is the only way in — and, because the gate
/// swaps roots rather than pushing, the only way out is a state change.
///
/// Every action here goes to the `SessionStore`; the screens themselves stay
/// session-agnostic. Note what is *not* here: 17e. It is a deep-link
/// destination with no back chevron, so it belongs to the gate
/// (`.recovering`), not to this stack.
struct WelcomeFlow: View {
    let session: SessionStore

    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onCreateAccount: {
                    session.clearError()
                    path.append(.createAccount)
                },
                // Google verified the address, so no confirmation
                // interstitial: this lands straight in the shell.
                onGoogle: { Task { await session.signInWithGoogle() } },
                onSignIn: {
                    session.clearError()
                    path.append(.signIn)
                }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AuthRoute.self) { route in
                destination(route).toolbar(.hidden, for: .navigationBar)
            }
        }
        // An expired recovery link routes to 17d from wherever the user was —
        // including a cold launch straight into this flow.
        .onChange(of: session.expiredRecoveryLink, initial: true) { _, expired in
            guard expired else { return }
            path = [.forgotPassword(expired: true)]
            // The route carries the notice from here on, so the flag is done.
            session.consumeExpiredRecoveryLink()
        }
    }

    @ViewBuilder
    private func destination(_ route: AuthRoute) -> some View {
        switch route {
        case .signIn:
            SignInView(
                onBack: pop,
                onForgot: {
                    session.clearError()
                    path.append(.forgotPassword(expired: false))
                },
                onSubmit: { email, password in
                    Task { await session.signIn(email: email, password: password) }
                },
                error: signInError
            )
        case .createAccount:
            CreateAccountView(
                onBack: pop,
                onSubmit: { name, email, password in
                    Task {
                        // Confirmation is ON, so a successful signup yields no
                        // session — it always pushes to 17c, never to Home.
                        if await session.signUp(name: name, email: email, password: password) {
                            path.append(.confirmEmail(email))
                        }
                    }
                },
                error: session.lastError.map { AuthError(message: $0.signInMessage) }
            )
        case .confirmEmail(let email):
            ConfirmEmailView(
                email: email,
                onCheck: { await session.checkConfirmation() },
                onResend: { Task { await session.resendConfirmation(email: email) } },
                // "Wrong address?" is a fresh signup, not an edit: the
                // unverified account stays behind, inert (contract).
                onGoBack: pop
            )
        case .forgotPassword(let expired):
            ForgotPasswordView(
                showExpiredLinkNotice: expired,
                onBack: pop,
                onSend: { email in Task { await session.requestPasswordReset(email: email) } }
            )
        }
    }

    /// `SessionAuthError` -> what 17a renders. The mapping lives here because
    /// `WelcomeFlow` already owns the session; the screens take a plain value and
    /// stay session-agnostic.
    ///
    /// `emailNotConfirmed` is the one failure with a remedy, so it gets the resend
    /// action the auth flow contract asks for. Its copy is still the placeholder
    /// that shipped with `signInMessage` -- the contract specifies
    /// "verify-specific copy with a resend action" without writing the string, and
    /// inventing locked copy here would be worse than surfacing the placeholder.
    private var signInError: AuthError? {
        guard let error = session.lastError else { return nil }
        switch error {
        case .emailNotConfirmed:
            return AuthError(
                message: error.signInMessage,
                actionTitle: "Resend confirmation email",
                action: { Task { await session.resendConfirmation(email: session.email ?? "") } }
            )
        case .invalidCredentials, .rateLimited:
            return AuthError(message: error.signInMessage)
        }
    }

    private func pop() {
        // The error belongs to the attempt, not the session: leaving it set would
        // show a failed sign-in on 17d after tapping "Forgot password?".
        session.clearError()
        if !path.isEmpty { path.removeLast() }
    }
}

/// Routes inside the unauthenticated stack. 17e is deliberately absent — it
/// is a gate state, not a pushable screen.
enum AuthRoute: Hashable {
    case signIn
    case createAccount
    case confirmEmail(String)
    /// `expired` = arrived here from a dead recovery link, so the screen
    /// renders its notice.
    case forgotPassword(expired: Bool)
}

#Preview("Welcome flow") {
    @Previewable @State var session = SessionStore(provider: MockSessionProvider(scenario: .signedOut))
    WelcomeFlow(session: session)
}
