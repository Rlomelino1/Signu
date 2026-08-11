import Foundation
import Supabase
// `Supabase` does not surface `Auth.AuthError`'s members, so the typed error
// mapping below needs the module directly rather than the umbrella.
import Auth

/// Live `SessionProviding`. The SDK owns the session; this maps its API onto the
/// eleven affordances the locked screens (16a, 17a–17e) actually offer.
///
/// It shares `SupabaseClientProvider.shared` with the data provider on purpose.
/// `SessionProviding` deliberately never exposes a token — "the gate above it
/// never learns what a token is" — so the data provider cannot be handed one;
/// instead both talk to one client whose auth module holds the session, and
/// `client.from(…)` attaches whatever is current. Two clients would mean two
/// sessions, and the data provider would read as signed-out moments after the gate
/// said otherwise.
@MainActor
final class SupabaseSessionProvider: SessionProviding {

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    /// Read from the SDK's stored session, so 17e can render the address without
    /// the gate ever seeing a token.
    var currentEmail: String? { client.auth.currentUser?.email }

    // MARK: - Restore

    /// Cold launch. `.recovering` is never produced here: it exists only as the
    /// result of a reset deep link, and a restored session is by definition one the
    /// user already completed. Returning it on restore would strand someone on 17e
    /// every launch.
    func restore() async -> AuthGateState {
        // `currentSession` is the stored session; touching `session` instead would
        // attempt a refresh and throw offline, turning a cold launch into a
        // sign-out.
        client.auth.currentSession == nil ? .unauthenticated : .authenticated
    }

    // MARK: - 17a / 17b

    func signIn(email: String, password: String) async throws {
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Confirmation is ON, so this never yields a usable session — 17b always
    /// pushes to 17c. The name rides along in user metadata, which is where the
    /// signup trigger's `display_name` fallback reads it from (v11).
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

    /// Google verified the address, so there is no confirmation interstitial: this
    /// lands straight in `.authenticated`.
    ///
    /// The SDK presents `ASWebAuthenticationSession` and performs the PKCE
    /// exchange itself, which is the reason the SDK was chosen over a hand-rolled
    /// client. It reads the redirect from the client's `redirectToURL`.
    func signInWithGoogle() async throws {
        do {
            _ = try await client.auth.signInWithOAuth(provider: .google)
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: - 17c

    func resendConfirmation(email: String) async throws {
        do {
            try await client.auth.resend(email: email, type: .signup)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// 17c's manual "I've confirmed my email", for the wrong-device case where the
    /// link fired on a laptop. A fresh `user(...)` call, not the cached one, or it
    /// would answer with whatever was true at sign-up.
    func checkConfirmation() async throws -> Bool {
        do {
            return try await client.auth.user().emailConfirmedAt != nil
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: - 17d / 17e

    /// Succeeds unconditionally by contract — enumeration-safe, so the screen may
    /// never claim a send happened. A thrown error would leak whether the address
    /// exists, so genuine failures are swallowed deliberately.
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
        // `.local` on purpose: signing out on this device must not invalidate the
        // user's other sessions, which `.global` would.
        try? await client.auth.signOut(scope: .local)
    }

    // MARK: - Deep links

    /// Resolves `signu://auth-callback`. Three outcomes the gate distinguishes, and
    /// the ordering matters.
    ///
    /// Recovery is detected from the URL BEFORE the exchange, not after. Once
    /// exchanged, a recovery link and a confirmation link both leave an ordinary
    /// live session behind — indistinguishable — and treating a recovery as
    /// `.authenticated` would drop the user into the app with the OLD password
    /// still set, which is the exact case `.recovering` exists to prevent.
    func handleAuthCallback(_ url: URL) async -> AuthCallbackOutcome? {
        guard url.scheme == URL(string: SupabaseConfig.redirectURL)?.scheme else { return nil }

        let isRecovery = Self.isRecovery(url)
        do {
            let session = try await client.auth.session(from: url)
            return isRecovery ? .recovering(email: session.user.email) : .authenticated
        } catch {
            // An expired or already-used recovery link is the one failure with a
            // dedicated route (17d, with a notice). Everything else is not an auth
            // callback we can act on, and nil leaves the gate where it was rather
            // than ejecting a signed-in user — the defect the v16 amendment fixed.
            return isRecovery ? .expiredRecoveryLink : nil
        }
    }

    /// `type=recovery` appears in the query on PKCE links and in the fragment on
    /// implicit ones, so both are checked. Fragments are not parsed by
    /// `URLComponents.queryItems`, which is why this looks in two places.
    private static func isRecovery(_ url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if components?.queryItems?.contains(where: { $0.name == "type" && $0.value == "recovery" }) == true {
            return true
        }
        return (components?.fragment ?? "").contains("type=recovery")
    }

    // MARK: - Error mapping

    /// Supabase's failures onto the three the contract names.
    ///
    /// `emailNotConfirmed` is kept distinct because Supabase returns a specific
    /// code for it and 17a renders a different state with a resend action — folding
    /// it into `invalidCredentials` would tell someone to check a password that was
    /// correct.
    ///
    /// Everything unrecognised becomes `invalidCredentials`, which is
    /// enumeration-safe by design: the contract refuses to say whether an account
    /// exists or how it signs in, so a vaguer error is the correct one, not a
    /// lossy one.
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
