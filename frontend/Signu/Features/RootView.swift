import SwiftUI

/// The auth gate, and nothing else. Four states, one for each thing the app
/// can legitimately be showing at launch; the tab shell is one of them, not
/// the default (see `AppShellView`).
///
/// Transitions are **crossfade root swaps**, never pushes — which is what
/// makes "no back gesture from the shell to WelcomeFlow" structural rather
/// than something to suppress.
struct RootView: View {
    var session: SessionStore

    /// Built on entry to `.authenticated`, dropped on exit — the gate
    /// boundary is the provider boundary.
    @State private var provider: SignuDataProviding?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(session: SessionStore) {
        self.session = session
        #if DEBUG
        FontDiagnostics.runIfRequested()
        #endif
    }

    var body: some View {
        #if DEBUG
        // Screenshot harnesses: `simctl launch … pro.sinatra.signu --hero-states[=0,1]`
        if let heroArg = CommandLine.arguments.first(where: { $0.hasPrefix("--hero-states") }) {
            let indices = heroArg.split(separator: "=").dropFirst().first
                .map { $0.split(separator: ",").compactMap { Int($0) } } ?? []
            if indices.isEmpty {
                HeroStatesGallery()
            } else {
                HeroStatesGallery(indices: indices)
            }
        } else if CommandLine.arguments.contains("--gallery-center") {
            DesignSystemGallery(anchor: .center)
        } else if CommandLine.arguments.contains("--gallery-bottom") {
            DesignSystemGallery(anchor: .bottom)
        } else if CommandLine.arguments.contains("--gallery") {
            DesignSystemGallery()
        } else if CommandLine.arguments.contains("--home-watching") {
            HomeScreen(provider: MockDataProvider(scenario: .freshConnection))
        } else if CommandLine.arguments.contains("--home-nobank") {
            HomeScreen(provider: MockDataProvider(scenario: .noBank))
        } else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--detail=") }) {
            DetailDebugView(
                name: String(arg.dropFirst("--detail=".count)),
                bottom: CommandLine.arguments.contains("--detail-bottom")
            )
        } else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--settings=") }) {
            SettingsDebugView(name: String(arg.dropFirst("--settings=".count)))
        } else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--auth=") }) {
            AuthDebugView(name: String(arg.dropFirst("--auth=".count)))
        } else {
            // `--gate=…` / `--welcome` / `--link=…` all run through the real
            // gate rather than a separate demo host.
            gate
        }
        #else
        gate
        #endif
    }

    private var gate: some View {
        ZStack {
            SignuColor.paper.ignoresSafeArea()

            switch session.gateState {
            case .restoring:
                SplashView()
                    .transition(.opacity)

            case .unauthenticated:
                WelcomeFlow(session: session)
                    .transition(.opacity)

            case .recovering:
                // 17e, standalone and with no back chevron: the reset link is
                // not part of a navigation stack, so there is nothing to pop
                // to. Its submit is the only exit (or an app kill).
                NewPasswordView(
                    email: session.email ?? "",
                    onSubmit: { password in
                        Task { await session.updatePassword(password) }
                    },
                    // NOT signInMessage: that copy is 17a's ("Couldn't sign in.
                    // Check your password…") and would be actively wrong here.
                    // SessionAuthError has no case describing a failed password
                    // update, and `authError()` funnels unknowns to
                    // .invalidCredentials, so rendering it raw would mislead.
                    //
                    // PLACEHOLDER COPY, flagged like signInMessage's own
                    // emailNotConfirmed string: the auth flow contract never
                    // specified 17e failure copy, and inventing locked wording is
                    // worse than surfacing something honest and saying so.
                    error: session.lastError == nil ? nil : AuthError(
                        message: "Couldn't set your new password. Try again."
                    )
                )
                .transition(.opacity)

            case .authenticated:
                // nil only for the single frame between the state flip and
                // the provider being built below — hidden under the crossfade.
                if let provider {
                    AppShellView(
                        provider: provider,
                        onSignOut: { Task { await session.signOut() } },
                        // The address comes from the session, which is why v19
                        // renders no form here. Guarded rather than defaulted to
                        // "": an empty address would be a send that always fails,
                        // behind copy claiming a link is on its way.
                        onSetPassword: {
                            guard let address = session.email else { return }
                            Task { await session.requestPasswordReset(email: address) }
                        }
                    )
                    .transition(.opacity)
                }
            }
        }
        // Crossfade, not a push. Reduce Motion gets no animation at all —
        // same accessibility posture as the v13 tab bar.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: session.gateState)
        .task {
            await session.restore()
        }
        .onChange(of: session.gateState, initial: true) { _, state in
            // The gate boundary is also the provider boundary: the real
            // provider will need a user_id, and stale rows must not survive a
            // sign-out. So it is constructed on entry and released on exit
            // rather than held globally and merely hidden.
            if state == .authenticated {
                if provider == nil { provider = SignuDataProviderFactory.make() }
            } else {
                provider = nil
            }
        }
        #if DEBUG
        .onAppear {
            session.fireLaunchLinkIfRequested()
        }
        #endif
    }
}

#if DEBUG
/// Screenshot harness for detail variants: `--detail=<name>` where name is
/// netflix / globoplay / spotify / amazon / cancelled / max, plus optional
/// `--detail-bottom` to open scrolled to the run start (21l).
private struct DetailDebugView: View {
    let name: String
    let bottom: Bool

    private let provider = MockDataProvider()
    private let serviceNames = [
        "netflix": "Netflix", "globoplay": "Globoplay",
        "spotify": "Spotify", "amazon": "Amazon Prime", "mubi": "MUBI",
    ]

    var body: some View {
        let anchor: UnitPoint = bottom ? .bottom : .top
        switch name {
        case "cancelled":
            let (sub, runs, charges) = MockDataProvider.demoCancelledTrailing()
            DetailScreen(payload: provider.detailPayload(subscription: sub, runs: runs, charges: charges), scrollAnchor: anchor)
        case "max":
            let (sub, runs, charges) = MockDataProvider.demoMax()
            DetailScreen(payload: provider.detailPayload(subscription: sub, runs: runs, charges: charges), scrollAnchor: anchor)
        default:
            DetailScreen(loader: {
                let service = serviceNames[name] ?? "Netflix"
                guard let sub = (try? await provider.subscriptions())?.first(where: { $0.serviceName == service })
                else { return nil }
                return try? await provider.detailPayload(subscriptionId: sub.id)
            }, scrollAnchor: anchor)
        }
    }
}
#endif

#if DEBUG
/// Screenshot harness for settings sub-screens: `--settings=<name>` where
/// name is connection-itau / connection-nubank / connection-bradesco /
/// attributed-itau / remove / delete.
private struct SettingsDebugView: View {
    let name: String
    private let provider = MockDataProvider()
    @State private var deleteScope: DeleteAccountScope?

    var body: some View {
        switch name {
        case "connection-itau", "connection-nubank", "connection-bradesco":
            ConnectionDetailScreen(provider: provider, connectionId: connId(String(name.dropFirst("connection-".count))))
        case "attributed-itau":
            AttributedSubsScreen(provider: provider, connectionId: connId("itau"))
        case "remove":
            SignuColor.paper.ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    RemoveBankSheet(institutionName: "Itaú", count: 11)
                        .presentationDetents([.height(560)])
                        .presentationDragIndicator(.visible)
                }
        case "delete":
            SignuColor.paper.ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    Group {
                        if let deleteScope {
                            DeleteAccountSheet(scope: deleteScope)
                                .presentationDetents([.height(560)])
                                .presentationDragIndicator(.visible)
                        } else {
                            Color.clear
                        }
                    }
                    .task { deleteScope = try? await provider.deleteAccountScope() }
                }
        default:
            SettingsScreen(provider: provider)
        }
    }

    private func connId(_ key: String) -> UUID {
        let map = ["itau": "Itaú", "nubank": "Nubank", "bradesco": "Bradesco"]
        return provider.connectionList.first { $0.institutionName == (map[key] ?? "Itaú") }?.id ?? UUID()
    }
}
#endif

#if DEBUG
/// Screenshot harness for individual auth screens: `--auth=<name>` where
/// name is signin / create / confirm / forgot / newpassword / expired.
/// Renders each screen in isolation, outside the gate.
private struct AuthDebugView: View {
    let name: String
    var body: some View {
        switch name {
        case "create": CreateAccountView()
        case "confirm": ConfirmEmailView(email: "marina.duarte@example.com")
        case "forgot": ForgotPasswordView()
        case "expired": ForgotPasswordView(showExpiredLinkNotice: true)
        case "newpassword": NewPasswordView(email: "marina.duarte@example.com")
        default: SignInView()
        }
    }
}
#endif

// MARK: - Gate previews

// One per gate state. Review each on **iPhone 17 Pro and 17 Pro Max** (v15
// preview convention) using the canvas device picker: `previewDevice` is
// ignored inside the `#Preview` macro — the compiler says so outright — which
// is why no preview in this project specifies a device in code.

#Preview("Gate · restoring (splash)") {
    @Previewable @State var session = SessionStore(provider: MockSessionProvider(scenario: .restoring))
    RootView(session: session)
}

#Preview("Gate · unauthenticated (16a)") {
    @Previewable @State var session = SessionStore(provider: MockSessionProvider(scenario: .signedOut))
    RootView(session: session)
}

#Preview("Gate · recovering (17e)") {
    @Previewable @State var session = SessionStore(provider: MockSessionProvider(scenario: .recovery))
    RootView(session: session)
}

#Preview("Gate · authenticated (shell)") {
    @Previewable @State var session = SessionStore(provider: MockSessionProvider(scenario: .signedIn))
    RootView(session: session)
}
