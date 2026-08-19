import Foundation

enum ProfileName {

    static func resolve(stored: String?, email: String) -> (display: String, isFallback: Bool) {
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return (email, true) }

        let isEmail = trimmed.localizedCaseInsensitiveCompare(
            email.trimmingCharacters(in: .whitespacesAndNewlines)
        ) == .orderedSame
        return (trimmed, isEmail)
    }
}
