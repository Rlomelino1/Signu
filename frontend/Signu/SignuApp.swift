import SwiftUI

@main
struct SignuApp: App {
    /// Owned here, above the gate, so it survives every root swap.
    @State private var session = SessionStore(provider: SignuApp.sessionProvider())

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                // Attached at the app root, NOT inside WelcomeFlow: auth
                // callbacks fire in both unauthenticated (confirm, recovery)
                // and authenticated states, so no screen below the gate can
                // own this.
                .onOpenURL { session.handle(url: $0) }
        }
    }

    private static func sessionProvider() -> SessionProviding {
        #if DEBUG
        // Opt IN to live auth, matching how SignuDataProviderFactory splits, so the
        // two never disagree about which world a build is in. Every existing launch
        // scenario keeps working untouched:
        //   simctl launch … pro.sinatra.signu --live-auth --live-data
        if CommandLine.arguments.contains("--live-auth") {
            return SupabaseSessionProvider()
        }
        return MockSessionProvider(scenario: MockSessionProvider.launchScenario)
        #else
        return SupabaseSessionProvider()
        #endif
    }
}
