import Foundation

enum AuthGateState: Equatable {
    case restoring
    case unauthenticated
    case recovering
    case authenticated
}

@MainActor
protocol SessionProviding {
    func restore() async -> AuthGateState

    func signIn(email: String, password: String) async throws
    func signUp(name: String, email: String, password: String) async throws
    func signInWithGoogle() async throws
    func resendConfirmation(email: String) async throws
    func checkConfirmation() async throws -> Bool
    func requestPasswordReset(email: String) async throws
    func updatePassword(_ password: String) async throws
    func signOut() async

    func handleAuthCallback(_ url: URL) async -> AuthCallbackOutcome?

    var currentEmail: String? { get }

    func sessionEndings() -> AsyncStream<Void>
}

enum AuthCallbackOutcome: Equatable {
    case authenticated
    case recovering(email: String?)
    case expiredRecoveryLink
}

enum SessionAuthError: Error, Equatable {
    case invalidCredentials
    case emailNotConfirmed
    case rateLimited
}

extension SessionAuthError {
    var signInMessage: String {
        switch self {
        case .invalidCredentials:
            "Couldn't sign in. Check your password — if you signed up with Google you need to set a password first by tapping on Forgot password, or go back and continue with Google."
        case .emailNotConfirmed:
            "Your email isn't confirmed yet."
        case .rateLimited:
            "Too many attempts. Try again in a moment."
        }
    }
}
