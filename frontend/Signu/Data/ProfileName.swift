import Foundation

/// Whether `profiles.display_name` is a name the user gave, or an address standing
/// in for one.
///
/// **The column is never null for a real account.** Migration #1's signup trigger
/// coalesces Google's `full_name` → 17b's `name` → **`new.email`**, deliberately
/// (v11): the row records which provider supplied the value, so a null there would
/// lose information. The consequence is that "no name" is stored as *the email
/// address*, not as nothing.
///
/// v47 missed this. It keyed the fallback on `display_name == nil`, which is true
/// only for fixtures — so Home kept greeting the production account with its own
/// email address, the very thing v47 set out to stop, while every test passed.
///
/// So the comparison is against the email, and a nil or blank value still counts:
/// three different ways of saying "this user never chose a name", one answer.
enum ProfileName {

    /// - Returns: the name to display, and whether it is standing in for a name the
    ///   user never gave. The display value is never empty — an address is a poor
    ///   name but a blank row is worse — and `isFallback` is what lets a greeting
    ///   decline to use it.
    static func resolve(stored: String?, email: String) -> (display: String, isFallback: Bool) {
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return (email, true) }

        // Case-insensitively, because an address is case-insensitive in its domain
        // and users type their own inconsistently. `localizedCaseInsensitiveCompare`
        // rather than lowercasing both: it does the right thing for non-ASCII
        // addresses without this needing to know why.
        let isEmail = trimmed.localizedCaseInsensitiveCompare(
            email.trimmingCharacters(in: .whitespacesAndNewlines)
        ) == .orderedSame
        return (trimmed, isEmail)
    }
}
