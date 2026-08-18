import Foundation

/// What to put on screen when a connection attempt fails.
///
/// The connect surface has two very different sources of failure, and only one of
/// them writes sentences:
///
///  * **Signu's own functions** answer `{"error": "…"}` with a sentence written for
///    a user ("Master ···· 2049 is already connected through Nu Pagamentos S.A."),
///    which the provider already surfaces. Those pass through untouched — v30's rule
///    that the server's own words beat a generic apology.
///  * **Pluggy Connect** answers with an enum. `ITEM_USER_ALREADY_EXISTS` reached a
///    user verbatim on 2026-08-17, which is a code where a sentence belongs.
///
/// So this translates the codes it can defend and leaves everything else alone.
///
/// **The unknown case keeps the original text rather than replacing it.** A generic
/// "something went wrong" would delete the only diagnostic the screen has, and this
/// project has already paid for that once: v40 spent an hour on a "permission
/// denied" message four steps from its cause. An unrecognised code is shown as-is,
/// with a line saying what to do about it.
enum ConnectErrorCopy {

    /// Codes whose meaning is established — seen in this project or documented
    /// unambiguously by Pluggy. Deliberately short: inventing copy for a code whose
    /// exact trigger is unverified would replace an accurate enum with a confident
    /// sentence that might be wrong, which is worse than the enum.
    private static let known: [String: String] = [
        "ITEM_USER_ALREADY_EXISTS":
            "This bank is already connected. Remove it in Settings first if you want to connect it again.",
        "INVALID_CREDENTIALS":
            "Those sign-in details didn't work. Check them with your bank and try again.",
        "INVALID_CREDENTIALS_MFA":
            "That code wasn't accepted. Request a new one from your bank and try again.",
        "ACCOUNT_LOCKED":
            "Your bank has locked this login. Unlock it with the bank, then try again.",
        "USER_AUTHORIZATION_NOT_GRANTED":
            "Your bank didn't grant access. Try again and approve the request when it appears.",
        "USER_INPUT_TIMEOUT":
            "The bank's login timed out. Try again — it usually needs a code within a minute.",
        "CONNECTION_ERROR":
            "Your bank couldn't be reached. This is usually temporary; try again shortly.",
        "SITE_NOT_AVAILABLE":
            "Your bank's systems are unavailable right now. Try again later.",
        // Not the bank's doing, and the ONLY code here where retrying is guaranteed
        // to fail. Pluggy refuses item creation for real bank connectors on a trial
        // plan; MeuPluggy (connector 200) and sandbox connectors are exempt, which is
        // why every existing connection was made without hitting this. Verified on
        // 2026-08-18: sandbox item creation returned 200 on the same credentials that
        // produced this code in the widget, and the dashboard showed the trial live
        // with 7 days left -- so this is a plan boundary, not an expiry.
        //
        // It is in this table precisely because the generic fallback said "trying
        // again often clears it" and offered a Try again button that could never
        // work. An accurate enum beats a confident wrong sentence (see below), but a
        // sentence that sends the user to press a dead button is worse than either.
        "TRIAL_CLIENT_ITEM_CREATE_NOT_ALLOWED":
            "Connecting this bank directly needs Pluggy production access, which this "
            + "project doesn't have yet. Retrying won't help — connecting through "
            + "MeuPluggy still works.",
    ]

    /// - Parameter raw: whatever the widget or the function produced — a code, a
    ///   sentence, or an empty string.
    static func message(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "The connection didn't complete. Try again."
        }
        if let known = known[trimmed.uppercased()] { return known }

        // Not a code we translate. A CODE_SHAPED string gets a sentence appended so
        // the screen says something actionable without hiding the original; anything
        // already sentence-shaped (Signu's own errors, Pluggy's prose) is left
        // exactly as written.
        guard isCodeShaped(trimmed) else { return trimmed }
        return "\(trimmed) — your bank reported this and Signu can't interpret it. "
            + "Trying again often clears it; if it repeats, this code is what to search for."
    }

    /// SCREAMING_SNAKE_CASE with no spaces: how every Pluggy code arrives, and
    /// nothing a person would have written.
    private static func isCodeShaped(_ text: String) -> Bool {
        guard !text.contains(" "), text.count > 3 else { return false }
        return text.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
    }
}
