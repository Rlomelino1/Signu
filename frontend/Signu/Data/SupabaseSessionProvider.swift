import Foundation
import Supabase
import Auth

@MainActor
final class SupabaseSessionProvider: SessionProviding {

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    var currentEmail: String? { client.auth.currentUser?.email }

    func sessionEndings() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, _) in client.auth.authStateChanges {
                    if event == .signedOut { continuation.yield(()) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }


    func restore() async -> AuthGateState {
        client.auth.currentSession == nil ? .unauthenticated : .authenticated
    }


    func signIn(email: String, password: String) async throws {
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            throw Self.mapped(error)
        }
    }

    func signUp(name: String, email: String, password: String) async throws {
        do {
            _ = try await client.auth.signUp(
                email: email,
                password: password,
                data: ["full_name": .string(name)]
            )
        } catch {
            throw Self.mapped(error)
        }
    }

    func signInWithGoogle() async throws {
        do {
            _ = try await client.auth.signInWithOAuth(provider: .google)
        } catch {
            throw Self.mapped(error)
        }
    }


    func resendConfirmation(email: String) async throws {
        do {
            try await client.auth.resend(email: email, type: .signup)
        } catch {
            throw Self.mapped(error)
        }
    }

    func checkConfirmation() async throws -> Bool {
        do {
            return try await client.auth.user().emailConfirmedAt != nil
        } catch {
            throw Self.mapped(error)
        }
    }


    func requestPasswordReset(email: String) async throws {
        try? await client.auth.resetPasswordForEmail(email)
    }

    func updatePassword(_ password: String) async throws {
        do {
            _ = try await client.auth.update(user: UserAttributes(password: password))
        } catch {
            throw Self.mapped(error)
        }
    }

    func signOut() async {
        try? await client.auth.signOut(scope: .local)
    }


    func handleAuthCallback(_ url: URL) async -> AuthCallbackOutcome? {
        guard url.scheme == URL(string: SupabaseConfig.redirectURL)?.scheme else { return nil }

        let isRecovery = Self.isRecovery(url)
        do {
            let session = try await client.auth.session(from: url)
            return isRecovery ? .recovering(email: session.user.email) : .authenticated
        } catch {
            return isRecovery ? .expiredRecoveryLink : nil
        }
    }

    private static func isRecovery(_ url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.queryItems?.contains(where: { $0.name == "type" && $0.value == "recovery" }) == true {
            return true
        }
        return (components?.fragment ?? "").contains("type=recovery")
    }


    private static func mapped(_ error: Error) -> SessionAuthError {
        if let authError = error as? Auth.AuthError {
            switch authError.errorCode {
            case .emailNotConfirmed, .emailAddressNotAuthorized:
                return .emailNotConfirmed
            case .overRequestRateLimit, .overEmailSendRateLimit:
                return .rateLimited
            default:
                return .invalidCredentials
            }
        }
        return .invalidCredentials
    }
}
