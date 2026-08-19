import SwiftUI

struct SettingsScreen: View {
    let provider: SignuDataProviding
    var actions = SettingsActions()

    @State private var payload: SettingsPayload?

    var body: some View {
        Group {
            if let payload {
                SettingsView(payload: payload, actions: actions)
            } else {
                Color.clear
            }
        }
        .task { payload = try? await provider.settingsPayload() }
    }
}

struct SettingsActions {
    var onSelectBank: (UUID) -> Void = { _ in }
    var onEditProfile: () -> Void = {}
    var onConnectBank: () -> Void = {}
    var onRestore: (UUID) -> Void = { _ in }
    var onDeleteAccount: () -> Void = {}
    var onSetPassword: () -> Void = {}
    var onSignOut: () -> Void = {}
}

@Observable
final class PasswordLinkState {
    var sentAt: Date?
}

#if DEBUG
@MainActor
private enum PasswordSentHarness {
    static var armed = false
}
#endif

struct SettingsView: View {
    let payload: SettingsPayload
    var actions = SettingsActions()
    var scrollAnchor: UnitPoint = .top

    @State private var restored: Set<UUID> = []
    @Environment(PasswordLinkState.self) private var passwordLink: PasswordLinkState?
    @State private var localSentAt: Date?
    @State private var clock = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var sentAt: Date? { passwordLink?.sentAt ?? localSentAt }

    private var cooldown: Int { AuthCooldown.remaining(since: sentAt, now: clock) }

    private func sendPasswordLink() {
        let stamp = Date()
        passwordLink?.sentAt = stamp
        localSentAt = stamp
        actions.onSetPassword()
    }

    private func resetPasswordRowIfSettled() {
        guard AuthCooldown.shouldForget(sentAt: sentAt, now: Date()) else { return }
        passwordLink?.sentAt = nil
        localSentAt = nil
    }

    private var dismissed: [SettingsPayload.DismissedRow] {
        payload.dismissed.filter { !restored.contains($0.id) }
    }

    var body: some View {
        SignuScrollView(anchor: scrollAnchor) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Settings")
                    .font(.signuScreenTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                    .padding(.top, 2)

                profileSection
                banksSection
                if !dismissed.isEmpty { dismissedSection }
                dataSection
            }
            .padding(.horizontal, SignuMetric.screenPadding)
            .padding(.bottom, SignuMetric.scrollBottomInset)
        }
        .background(SignuColor.paper)
        .onReceive(tick) { _ in clock = Date() }
        .onDisappear { resetPasswordRowIfSettled() }
        #if DEBUG
        .onAppear {
            guard !PasswordSentHarness.armed,
                  let arg = CommandLine.arguments.first(where: {
                      $0.hasPrefix("--settings-password-sent")
                  }),
                  sentAt == nil
            else { return }
            PasswordSentHarness.armed = true
            localSentAt = arg.hasSuffix("=expired")
                ? Date().addingTimeInterval(-Double(AuthCooldown.seconds + 10))
                : Date()
        }
        #endif
    }


    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Profile")
            SignuCard {
                VStack(spacing: 0) {
                    Button { actions.onEditProfile() } label: {
                        HStack(spacing: 14) {
                            ProfileAvatar(path: payload.avatarPath, initial: payload.initial, size: 46)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(payload.displayName)
                                    .font(.signuRowTitle)
                                    .foregroundStyle(SignuColor.textPrimary)
                                    .lineLimit(1)
                                Text(payload.displayNameIsFallback ? "Add your name" : payload.email)
                                    .font(SignuFont.font(14))
                                    .foregroundStyle(SignuColor.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            chevron
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if !payload.providers.isEmpty {
                        rowDivider
                        HStack(spacing: 8) {
                            Text("Sign-in methods")
                                .font(.signuBody)
                                .foregroundStyle(SignuColor.textPrimary)
                            Spacer(minLength: 8)
                            ForEach(payload.providers, id: \.self) { provider in
                                Text(provider)
                                    .font(.signuChip)
                                    .foregroundStyle(SignuColor.textPrimary)
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(SignuColor.sunken, in: Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                    }

                    rowDivider
                    passwordRow
                    rowDivider
                    signOutRow
                }
            }
        }
    }

    @ViewBuilder
    private var passwordRow: some View {
        if sentAt != nil {
            VStack(alignment: .leading, spacing: 2) {
                Text("Check \(payload.email) for a link to set your password.")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if cooldown > 0 {
                    Text("Resend available in \(cooldown)s")
                        .font(SignuFont.font(14))
                        .foregroundStyle(SignuColor.textSecondary)
                } else {
                    Button("Send another link", action: sendPasswordLink)
                    .font(SignuFont.font(14, .semibold))
                    .foregroundStyle(SignuColor.textPrimary)
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        } else {
            Button { sendPasswordLink() } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.hasPassword ? "Change password" : "Set a password")
                            .font(.signuBody)
                            .foregroundStyle(SignuColor.textPrimary)
                        if !payload.hasPassword {
                            Text("You sign in with Google. A password gives you a second way in.")
                                .font(SignuFont.font(14))
                                .foregroundStyle(SignuColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    chevron
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var signOutRow: some View {
        Button(action: actions.onSignOut) {
            HStack(spacing: 12) {
                Text("Sign out")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textPrimary)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    private var banksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Connected banks")
            if payload.banks.isEmpty {
                emptyBanksCard
            } else {
                SignuCard {
                    VStack(spacing: 0) {
                        ForEach(payload.banks) { bank in
                            Button { actions.onSelectBank(bank.id) } label: { bankRow(bank) }
                                .buttonStyle(.plain)
                            rowDivider
                        }
                        Button(action: actions.onConnectBank) { connectRow }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func bankRow(_ bank: SettingsPayload.BankRow) -> some View {
        HStack(spacing: 10) {
            ServiceAvatar(name: bank.name, kind: .institution)
            VStack(alignment: .leading, spacing: 1) {
                Text(bank.name)
                    .font(.signuRowTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                Text(bank.subtitle)
                    .font(SignuFont.font(14))
                    .foregroundStyle(subtitleColor(bank.chipTone))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatusChip(text: bank.chipText, tone: bank.chipTone, compact: true).fixedSize()
            chevron
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func subtitleColor(_ tone: StatusChip.Tone) -> Color {
        switch tone {
        case .danger: SignuColor.red
        case .warning: SignuColor.gold
        default: SignuColor.textSecondary
        }
    }

    private var connectRow: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(SignuColor.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .frame(width: 44, height: 44)
                .overlay { Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(SignuColor.textSecondary) }
            Text("Connect a bank")
                .font(.signuRowTitle)
                .foregroundStyle(SignuColor.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var emptyBanksCard: some View {
        SignuCard {
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(SignuColor.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(width: 60, height: 60)
                    .overlay { Image(systemName: "house").font(.system(size: 22)).foregroundStyle(SignuColor.textSecondary) }
                Text("No banks connected")
                    .font(.signuSection)
                    .foregroundStyle(SignuColor.textPrimary)
                Text("Subscriptions are detected from your card charges — connect a bank to start.")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Connect a bank", action: actions.onConnectBank)
                    .buttonStyle(SignuButtonStyle(kind: .primary, fullWidth: false))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }


    private var dismissedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Dismissed suggestions")
            SignuCard {
                VStack(spacing: 0) {
                    ForEach(Array(dismissed.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 12) {
                            ServiceAvatar(name: row.name)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name)
                                    .font(.signuRowTitle)
                                    .foregroundStyle(SignuColor.textPrimary)
                                Text(row.subtitle)
                                    .font(SignuFont.font(14))
                                    .foregroundStyle(SignuColor.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .layoutPriority(1)
                            Spacer(minLength: 8)
                            Button {
                                actions.onRestore(row.id)
                                withAnimation(.easeOut(duration: 0.2)) { _ = restored.insert(row.id) }
                            } label: {
                                Text("Restore").lineLimit(1)
                            }
                            .buttonStyle(SignuButtonStyle(kind: .secondary, fullWidth: false, compact: true))
                            .fixedSize()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        if index < dismissed.count - 1 { rowDivider }
                    }
                }
            }
        }
    }


    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Data")
            Button(action: actions.onDeleteAccount) {
                SignuCard {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete account")
                                .font(.signuRowTitle)
                                .foregroundStyle(SignuColor.red)
                            Text(payload.deleteScopeLine)
                                .font(SignuFont.font(14))
                                .foregroundStyle(SignuColor.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SignuColor.red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }


    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SignuColor.textTertiary)
    }

    private var rowDivider: some View {
        Rectangle().fill(SignuColor.hairline).frame(height: 1)
            .padding(.leading, SignuMetric.rowPaddingH)
    }
}

#Preview("Settings (12a)") { SettingsScreen(provider: MockDataProvider()) }
#Preview("Settings · no banks (12d)") { SettingsScreen(provider: MockDataProvider(scenario: .noBank)) }
#Preview("Settings · in shell") { AppShellView(provider: MockDataProvider(), initialTab: .settings) }
