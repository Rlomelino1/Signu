import SwiftUI

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
        .onChange(of: session.expiredRecoveryLink, initial: true) { _, expired in
            guard expired else { return }
            path = [.forgotPassword(expired: true)]
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
        session.clearError()
        if !path.isEmpty { path.removeLast() }
    }
}

enum AuthRoute: Hashable {
    case signIn
    case createAccount
    case confirmEmail(String)
    case forgotPassword(expired: Bool)
}

#Preview("Welcome flow") {
    @Previewable @State var session = SessionStore(provider: MockSessionProvider(scenario: .signedOut))
    WelcomeFlow(session: session)
}
