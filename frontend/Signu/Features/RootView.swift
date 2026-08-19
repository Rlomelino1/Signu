import SwiftUI

struct RootView: View {
    var session: SessionStore

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
        } else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--calendar") }) {
            CalendarDebugView(
                monthOffset: arg.split(separator: "=").dropFirst().first.flatMap { Int($0) } ?? 0
            )
        } else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--settings=") }) {
            SettingsDebugView(name: String(arg.dropFirst("--settings=".count)))
        } else if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--auth=") }) {
            AuthDebugView(name: String(arg.dropFirst("--auth=".count)))
        } else {
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
                NewPasswordView(
                    email: session.email ?? "",
                    onSubmit: { password in
                        Task { await session.updatePassword(password) }
                    },
                    error: session.lastError == nil ? nil : AuthError(
                        message: "Couldn't set your new password. Try again."
                    )
                )
                .transition(.opacity)

            case .authenticated:
                if let provider {
                    AppShellView(
                        provider: provider,
                        onSignOut: { Task { await session.signOut() } },
                        onSetPassword: {
                            guard let address = session.email else { return }
                            Task { await session.requestPasswordReset(email: address) }
                        }
                    )
                    .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: session.gateState)
        .task {
            await session.restore()
        }
        .onChange(of: session.gateState, initial: true) { _, state in
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
private struct CalendarDebugView: View {
    let monthOffset: Int
    private let provider = MockDataProvider()

    var body: some View {
        CalendarScreen(provider: provider, startingMonthOffset: monthOffset)
    }
}

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
        case "edit-profile", "edit-profile-unnamed":
            SignuColor.paper.ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    EditProfileSheet(provider: provider)
                        .environment(AvatarStore())
                        .presentationDetents([.height(460)])
                        .presentationDragIndicator(.visible)
                }
                .task {
                    if name.hasSuffix("unnamed") { try? await provider.setDisplayName(nil) }
                }
        case "remove":
            SignuColor.paper.ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    RemoveBankSheet(institutionName: "Demo Bank", count: 11)
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
        let map = ["demobank": "Demo Bank", "mockbank": "Mock Bank", "samplebank": "Sample Bank"]
        return provider.connectionList.first { $0.institutionName == (map[key] ?? "Demo Bank") }?.id ?? UUID()
    }
}
#endif

#if DEBUG
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
