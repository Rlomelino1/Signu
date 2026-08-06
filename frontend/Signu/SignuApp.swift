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
        return MockSessionProvider(scenario: MockSessionProvider.launchScenario)
        #else
        // No SDK yet: a release build has no way to restore a session, so the
        // honest starting state is signed out.
        return MockSessionProvider(scenario: .signedOut)
        #endif
    }
}
