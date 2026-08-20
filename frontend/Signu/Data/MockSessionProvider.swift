import Foundation

@MainActor
final class MockSessionProvider: SessionProviding {
    enum Scenario {
        case signedOut
        case signedIn
        case restoring
        case recovery
    }

    enum MockInput {
        static let password = "Signu123"
        static let unverified = "unverified@"
        static let rateLimited = "ratelimit@"
        static let confirmed = "confirmed@"
    }

    static let restoreDelay = Duration.milliseconds(400)
    private static let actionDelay = Duration.milliseconds(250)

    private let scenario: Scenario
    private let sessionEmail: String
    private(set) var currentEmail: String?
    private var pendingConfirmationEmail: String?

    init(scenario: Scenario = .signedOut, sessionEmail: String = "alex.rivera@example.test") {
        self.scenario = scenario
        self.sessionEmail = sessionEmail
    }


    func sessionEndings() -> AsyncStream<Void> {
        AsyncStream { continuation in
            guard CommandLine.arguments.contains("--session-ends") else { return }
            let task = Task {
                try? await Task.sleep(for: .seconds(2))
                continuation.yield(())
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func restore() async -> AuthGateState {
        try? await Task.sleep(for: Self.restoreDelay)
        switch scenario {
        case .signedOut:
            return .unauthenticated
        case .signedIn:
            currentEmail = sessionEmail
            return .authenticated
        case .restoring:
            return .restoring
        case .recovery:
            currentEmail = sessionEmail
            return .recovering
        }
    }

    func signIn(email: String, password: String) async throws {
        try await Task.sleep(for: Self.actionDelay)
        if email.lowercased().contains(MockInput.unverified) {
            throw SessionAuthError.emailNotConfirmed
        }
        guard password == MockInput.password else {
            throw SessionAuthError.invalidCredentials
        }
        currentEmail = email
    }

    func signUp(name: String, email: String, password: String) async throws {
        try await Task.sleep(for: Self.actionDelay)
        pendingConfirmationEmail = email
    }

    func signInWithGoogle() async throws {
        try await Task.sleep(for: Self.actionDelay)
        currentEmail = sessionEmail
    }

    func resendConfirmation(email: String) async throws {
        try await Task.sleep(for: Self.actionDelay)
        if email.lowercased().contains(MockInput.rateLimited) {
            throw SessionAuthError.rateLimited
        }
    }

    func checkConfirmation() async throws -> Bool {
        try await Task.sleep(for: Self.actionDelay)
        let address = pendingConfirmationEmail ?? ""
        guard address.lowercased().contains(MockInput.confirmed) else { return false }
        currentEmail = address
        return true
    }

    func requestPasswordReset(email: String) async throws {
        try await Task.sleep(for: Self.actionDelay)
    }

    func updatePassword(_ password: String) async throws {
        try await Task.sleep(for: Self.actionDelay)
        if currentEmail == nil { currentEmail = sessionEmail }
    }

    func signOut() async {
        currentEmail = nil
        pendingConfirmationEmail = nil
    }

    func handleAuthCallback(_ url: URL) async -> AuthCallbackOutcome? {
        let mock = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "mock" }?.value
        switch mock {
        case "confirm":
            currentEmail = pendingConfirmationEmail ?? sessionEmail
            return .authenticated
        case "recovery":
            currentEmail = sessionEmail
            return .recovering(email: sessionEmail)
        case "expired":
            return .expiredRecoveryLink
        default:
            return nil
        }
    }
}

#if DEBUG
extension MockSessionProvider {
    static var launchScenario: Scenario {
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--gate=") }) {
            switch String(arg.dropFirst("--gate=".count)) {
            case "restoring": return .restoring
            case "unauthenticated", "welcome": return .signedOut
            case "recovering", "recovery": return .recovery
            case "authenticated": return .signedIn
            default: break
            }
        }
        if CommandLine.arguments.contains("--welcome") { return .signedOut }
        return .signedIn
    }
}
#endif
