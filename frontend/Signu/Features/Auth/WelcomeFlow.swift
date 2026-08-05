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
                onCreateAccount: { path.append(.createAccount) },
                // Google verified the address, so no confirmation
                // interstitial: this lands straight in the shell.
                onGoogle: { Task { await session.signInWithGoogle() } },
                onSignIn: { path.append(.signIn) }
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
                onForgot: { path.append(.forgotPassword(expired: false)) },
                onSubmit: { email, password in
                    Task { await session.signIn(email: email, password: password) }
                }
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
                }
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

    private func pop() {
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
