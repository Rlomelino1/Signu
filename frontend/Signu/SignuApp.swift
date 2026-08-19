import SwiftUI

@main
struct SignuApp: App {
    @State private var session = SessionStore(provider: SignuApp.sessionProvider())

    init() {
        ReminderOffer.resetIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .onOpenURL { session.handle(url: $0) }
        }
    }

    private static func sessionProvider() -> SessionProviding {
        #if DEBUG
        if CommandLine.arguments.contains("--live-auth") {
            return SupabaseSessionProvider()
        }
        return MockSessionProvider(scenario: MockSessionProvider.launchScenario)
        #else
        return SupabaseSessionProvider()
        #endif
    }
}
