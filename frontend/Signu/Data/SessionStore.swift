import Foundation

@MainActor
@Observable
final class SessionStore {
    private(set) var gateState: AuthGateState = .restoring

    private(set) var email: String?

    private(set) var lastError: SessionAuthError?

    func clearError() { lastError = nil }

    private(set) var expiredRecoveryLink = false

    @ObservationIgnored private let provider: SessionProviding

    init(provider: SessionProviding) {
        self.provider = provider
    }


    enum GateEvent: Equatable {
        case restored(AuthGateState)
        case signedIn(email: String?)
        case confirmLink
        case recoveryLink(email: String?)
        case expiredRecoveryLink
        case passwordUpdated
        case signedOut
        case sessionEnded
    }

    private func apply(_ event: GateEvent) {
        switch event {

        case .restored(let restored):
            switch gateState {
            case .restoring:
                email = provider.currentEmail
                if restored == .authenticated { expiredRecoveryLink = false }
                gateState = restored
            case .unauthenticated, .recovering, .authenticated:
                break
            }

        case .signedIn(let address):
            switch gateState {
            case .restoring, .unauthenticated:
                email = address ?? provider.currentEmail
                gateState = .authenticated
            case .recovering:
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
                break
            case .authenticated:
                break
            }

        case .recoveryLink(let address):
            switch gateState {
            case .restoring, .unauthenticated, .recovering, .authenticated:
                email = address ?? provider.currentEmail ?? email
                expiredRecoveryLink = false
                gateState = .recovering
            }

        case .expiredRecoveryLink:
            switch gateState {
            case .unauthenticated:
                expiredRecoveryLink = true
            case .restoring:
                expiredRecoveryLink = true
            case .recovering, .authenticated:
                break
            }

        case .passwordUpdated:
            switch gateState {
            case .recovering:
                email = provider.currentEmail ?? email
                gateState = .authenticated
            case .restoring, .unauthenticated, .authenticated:
                break
            }

        case .signedOut:
            switch gateState {
            case .restoring, .unauthenticated, .recovering, .authenticated:
                email = nil
                lastError = nil
                expiredRecoveryLink = false
                gateState = .unauthenticated
            }

        case .sessionEnded:
            switch gateState {
            case .authenticated:
                email = nil
                gateState = .unauthenticated
            case .recovering:
                email = nil
                gateState = .unauthenticated
            case .restoring:
                break
            case .unauthenticated:
                break
            }
        }
    }


    func restore() async {
        apply(.restored(await provider.restore()))
        watchForSessionEnd()
    }

    @ObservationIgnored private var sessionWatch: Task<Void, Never>?

    private func watchForSessionEnd() {
        guard sessionWatch == nil else { return }
        sessionWatch = Task { [weak self] in
            guard let stream = self?.provider.sessionEndings() else { return }
            for await _ in stream {
                self?.apply(.sessionEnded)
            }
        }
    }


    func signIn(email address: String, password: String) async {
        lastError = nil
        do {
            try await provider.signIn(email: address, password: password)
            apply(.signedIn(email: provider.currentEmail ?? address))
        } catch {
            lastError = authError(error)
        }
    }

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

    func signInWithGoogle() async {
        lastError = nil
        do {
            try await provider.signInWithGoogle()
            apply(.signedIn(email: provider.currentEmail))
        } catch {
            lastError = authError(error)
        }
    }

    func resendConfirmation(email address: String) async {
        lastError = nil
        do {
            try await provider.resendConfirmation(email: address)
        } catch {
            lastError = authError(error)
        }
    }

    func checkConfirmation() async -> Bool {
        lastError = nil
        do {
            guard try await provider.checkConfirmation() else { return false }
            apply(.signedIn(email: provider.currentEmail ?? email))
            return gateState == .authenticated
        } catch {
            lastError = authError(error)
            return false
        }
    }

    func requestPasswordReset(email address: String) async {
        lastError = nil
        do {
            try await provider.requestPasswordReset(email: address)
        } catch {
            lastError = authError(error)
        }
    }

    func updatePassword(_ password: String) async {
        lastError = nil
        do {
            try await provider.updatePassword(password)
            apply(.passwordUpdated)
        } catch {
            lastError = authError(error)
        }
    }

    func signOut() async {
        await provider.signOut()
        apply(.signedOut)
    }


    static let urlScheme = "signu"
    static let authCallbackHost = "auth-callback"

    func handle(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme,
              url.host?.lowercased() == Self.authCallbackHost
        else { return }

        Task {
            guard let outcome = await provider.handleAuthCallback(url) else { return }
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

    func consumeExpiredRecoveryLink() {
        expiredRecoveryLink = false
    }


    private func authError(_ error: Error) -> SessionAuthError {
        error as? SessionAuthError ?? .invalidCredentials
    }
}

#if DEBUG
extension SessionStore {
    func fireLaunchLinkIfRequested() {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--link=") }) else { return }
        let name = String(arg.dropFirst("--link=".count))
        guard let url = URL(string: "\(Self.urlScheme)://\(Self.authCallbackHost)?mock=\(name)") else { return }
        handle(url: url)
    }
}
#endif
