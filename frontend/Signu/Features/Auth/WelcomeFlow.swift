import SwiftUI

/// The pre-auth navigation stack: Welcome → auth screens. Stub actions;
/// `onFinish` fires where a real build would hand off to a live session.
struct WelcomeFlow: View {
    var onFinish: () -> Void = {}

    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onCreateAccount: { path.append(.createAccount) },
                onGoogle: onFinish,                      // Google → no email confirmation
                onSignIn: { path.append(.signIn) }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AuthRoute.self) { route in
                destination(route).toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: AuthRoute) -> some View {
        switch route {
        case .signIn:
            SignInView(
                onBack: pop,
                onForgot: { path.append(.forgotPassword) },
                onSubmit: onFinish
            )
        case .createAccount:
            CreateAccountView(
                onBack: pop,
                onSubmit: { email in path.append(.confirmEmail(email)) }
            )
        case .confirmEmail(let email):
            ConfirmEmailView(email: email, onConfirmed: onFinish, onGoBack: pop)
        case .forgotPassword:
            ForgotPasswordView(onBack: pop)
        case .newPassword(let email):
            NewPasswordView(email: email, onSubmit: onFinish)
        }
    }

    private func pop() {
        if !path.isEmpty { path.removeLast() }
    }
}

enum AuthRoute: Hashable {
    case signIn
    case createAccount
    case confirmEmail(String)
    case forgotPassword
    case newPassword(String)
}

#Preview("Welcome flow") {
    WelcomeFlow()
}
