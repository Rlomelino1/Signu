import Foundation

enum ReminderOffer {
    private static let key = "signu.reminderOfferAnswered"

    static var answered: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func resetIfRequested() {
        #if DEBUG
        if CommandLine.arguments.contains("--fresh-reminder-offer") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        #endif
    }
}
