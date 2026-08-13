import Foundation

/// Whether the user has already been offered a reminder after confirming a
/// subscription (22b).
///
/// WHY THIS IS LOCAL AND NOT A COLUMN
///
/// The offer must not come back once answered, and "answered" has two halves
/// that are stored very differently:
///
///  * **Yes** is durable in the database already — the subscription now has a
///    `remind_before_days`, so `ReviewPayload.remindersNeverUsed` is false
///    everywhere, on every device, forever. Nothing extra is needed.
///  * **No** writes nothing, by design: declining a reminder must not leave a
///    mark on a subscription the user did not ask to change. So the only record
///    of it is this flag.
///
/// A `profiles` column would make the "no" durable across devices, at the cost
/// of a migration AND an extension of Migration #1's column-scoped UPDATE grant —
/// the boundary v29 and v30 exist to protect. For a single-user app the trade is
/// not worth it: the failure mode is that a reinstall asks once more, and the
/// question is one tap to decline.
enum ReminderOffer {
    private static let key = "signu.reminderOfferAnswered"

    static var answered: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Tests and screenshot runs need a known starting point, because
    /// `UserDefaults` survives between launches of the same install and would
    /// otherwise make the second run of a test behave differently from the first.
    static func resetIfRequested() {
        #if DEBUG
        if CommandLine.arguments.contains("--fresh-reminder-offer") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        #endif
    }
}
