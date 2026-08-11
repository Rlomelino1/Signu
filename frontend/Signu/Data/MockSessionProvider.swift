import Foundation

/// In-memory auth backend, mirroring `MockDataProvider`'s scenario switch.
/// No SDK, no tokens, no networking — only the state transitions the gate
/// reacts to, so the whole navigation edge is reviewable and scriptable.
@MainActor
final class MockSessionProvider: SessionProviding {
    /// Launch scenarios: the same provider drives every gate state.
    enum Scenario {
        case signedOut      // cold launch, no session → 16a
        case signedIn       // cold launch with a session → app shell
        case restoring      // parks on the splash, for reviewing it
        case recovery       // launched from a reset link → 17e
    }

    /// Designated mock inputs. Error injection rides on these rather than a
    /// UI toggle, so triggering a failure is the same gesture a real user
    /// makes — and the injection can't leak into a release build's UI.
    enum MockInput {
        /// The one password that signs in (and satisfies the locked policy:
        /// 8+ chars, 1 uppercase, 1 number). Anything else is wrong.
        static let password = "Signu123"
        /// Any address containing this yields `emailNotConfirmed` on 17a —
        /// the abandoned-17c user, whose copy variant is distinct from a
        /// plain wrong password.
        static let unverified = "unverified@"
        /// Any address containing this yields `rateLimited` on resend, so
        /// 17c's 120s cooldown copy is reachable.
        static let rateLimited = "ratelimit@"
        /// Signing up with an address containing this makes the manual
        /// "I've confirmed my email" check succeed; every other address
        /// returns false, exercising 17c's "Not confirmed yet" line.
        static let confirmed = "confirmed@"
    }

    /// Held on every launch so the splash is real and observable rather than
    /// a one-frame flash.
    static let restoreDelay = Duration.milliseconds(400)
    /// Stands in for a round trip, so button states are reviewable.
    private static let actionDelay = Duration.milliseconds(250)

    private let scenario: Scenario
    private let sessionEmail: String
    private(set) var currentEmail: String?
    /// The address 17b signed up with — what the manual confirmation check
    /// and the resend action work against.
    private var pendingConfirmationEmail: String?

    init(scenario: Scenario = .signedOut, sessionEmail: String = "rafael.souza@example.com") {
        self.scenario = scenario
        self.sessionEmail = sessionEmail
    }

    // MARK: - SessionProviding

    func restore() async -> AuthGateState {
        try? await Task.sleep(for: Self.restoreDelay)
        switch scenario {
        case .signedOut:
            return .unauthenticated
        case .signedIn:
            currentEmail = sessionEmail
            return .authenticated
        case .restoring:
            // Stays on the splash: returning `.restoring` leaves the gate
            // exactly where it started.
            return .restoring
        case .recovery:
            // As if the app had been launched by a reset link: session live,
            // password not yet changed.
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
        // No session on purpose — confirmation is ON, so 17b lands on 17c.
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
        // Unconditional success — enumeration-safe by contract.
    }

    func updatePassword(_ password: String) async throws {
        try await Task.sleep(for: Self.actionDelay)
        if currentEmail == nil { currentEmail = sessionEmail }
    }

    func signOut() async {
        currentEmail = nil
        pendingConfirmationEmail = nil
    }

    /// Maps `?mock=` to a transition, so the whole deep-link path is testable
    /// from the command line:
    ///
    ///     xcrun simctl openurl booted "signu://auth-callback?mock=recovery"
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
    /// `--gate=<state>` picks the launch scenario; `--welcome` is kept as the
    /// existing screenshot entry point for 16a, now routed through the real
    /// gate instead of a separate demo host.
    ///
    /// Defaults to `.signedIn` in DEBUG so every existing shell harness
    /// (`--shell-subs`, `--home-bottom`, `--autohide-demo`, `--settings=…`)
    /// still opens on the shell rather than being fenced behind 16a. Release
    /// builds default to `.signedOut` — see `SignuApp`.
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
