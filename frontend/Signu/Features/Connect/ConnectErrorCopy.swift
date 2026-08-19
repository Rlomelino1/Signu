import Foundation

enum ConnectErrorCopy {

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
        "TRIAL_CLIENT_ITEM_CREATE_NOT_ALLOWED":
            "Connecting this bank directly needs Pluggy production access, which this "
            + "project doesn't have yet. Retrying won't help — connecting through "
            + "MeuPluggy still works.",
    ]

    static func message(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "The connection didn't complete. Try again."
        }
        if let known = known[trimmed.uppercased()] { return known }

        guard isCodeShaped(trimmed) else { return trimmed }
        return "\(trimmed) — your bank reported this and Signu can't interpret it. "
            + "Trying again often clears it; if it repeats, this code is what to search for."
    }

    private static func isCodeShaped(_ text: String) -> Bool {
        guard !text.contains(" "), text.count > 3 else { return false }
        return text.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
    }
}
