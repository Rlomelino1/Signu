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
    /// The Profile row (v47). Opens the edit-profile sheet.
    var onEditProfile: () -> Void = {}
    var onConnectBank: () -> Void = {}
    var onRestore: (UUID) -> Void = { _ in }
    var onDeleteAccount: () -> Void = {}
    /// v19's password row. Sends 17d's reset link to the session's address — no
    /// screen is pushed, so this returns nothing and cannot fail visibly: the
    /// send is enumeration-safe by contract and swallows its errors.
    var onSetPassword: () -> Void = {}
    /// v19's sign-out row. No confirmation by contract; the gate turns this into
    /// a root swap back to 16a.
    var onSignOut: () -> Void = {}
}

/// The v19 password row's sent state, held above the screen.
///
/// `AppShellView`'s `switch selectedTab` destroys the branch it isn't rendering,
/// so state held inside `SettingsView` resets the moment the user visits Home and
/// comes back — and the countdown's only job is to stop a second tap inside
/// Supabase's ~60s window, which fails *silently* because the send is
/// enumeration-safe and swallows its errors. A cooldown that forgets is the bug
/// it was added to prevent.
///
/// A timestamp rather than a decrementing counter, for the same reason: a counter
/// only ticks while some view is alive to tick it, so two minutes spent on
/// another tab would leave 100s still on the clock.
///
/// Handed down through the environment like `TabBarState`, and read as an
/// optional there so a standalone `SettingsScreen` preview still works.
@Observable
final class PasswordLinkState {
    var sentAt: Date?
}

#if DEBUG
/// Whether the screenshot/UI-test harness has already armed the sent state.
///
/// Static because the thing it must outlive is the view: `switch selectedTab`
/// destroys `SettingsView`, so `@State` would reset on every return and the harness
/// would re-arm — masking the one behaviour v48's test exists to check.
///
/// `@MainActor` rather than `nonisolated(unsafe)`: it is only ever touched from
/// `onAppear`, which is already main-actor work, and the project is in the Swift 6
/// language mode where the unchecked form would be the loophole rather than the fix.
@MainActor
private enum PasswordSentHarness {
    static var armed = false
}
#endif

/// Settings (12a; empty-banks state = 12d).
struct SettingsView: View {
    let payload: SettingsPayload
    var actions = SettingsActions()
    var scrollAnchor: UnitPoint = .top

    @State private var restored: Set<UUID> = []
    /// The password row owns its own sent state (v19) — 17d is never rendered
    /// from here, so there is no screen to hold it. It lives in the environment so
    /// it outlives a tab switch; `localSentAt` is the fallback for the previews
    /// and screenshot runs that render this screen with no shell above it.
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

    /// Returns the row to its original state once the cooldown has fully elapsed
    /// AND the user has left the screen (v48).
    ///
    /// Nothing cleared `sentAt` before this, so one tap left "Check your email for a
    /// link" and a live Resend standing for the rest of the process — long after the
    /// 120s window they describe, and long after the mail was dealt with.
    ///
    /// **Both conditions are load-bearing.** Clearing on a timer while the user is
    /// looking at the row would pull the confirmation out from under them
    /// mid-sentence, which is worse than a stale row. And clearing on exit *during*
    /// the cooldown would defeat the reason the state lives above this view at all
    /// (v19): the countdown has to survive a tab switch, because a Resend that
    /// silently no-ops inside Supabase's window is the failure it exists to prevent.
    ///
    /// So: leaving is the trigger, an expired cooldown is the condition.
    private func resetPasswordRowIfSettled() {
        // `Date()` rather than the ticked `clock`, which can be up to a second
        // stale: this runs on the way out, when no tick is coming to correct it.
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
        // Leaving is the trigger; an expired cooldown is the condition. See
        // `resetPasswordRowIfSettled` for why it is both and not either.
        .onDisappear { resetPasswordRowIfSettled() }
        #if DEBUG
        // The sent state is otherwise reachable only by tapping, which no
        // screenshot run can do.
        //
        // `--settings-password-sent=expired` backdates the stamp past the window, so
        // v48's reset can be exercised without a 120-second test.
        //
        // ARMED ONCE PER LAUNCH, not per appearance: re-arming on return would put
        // the sent state back exactly when the test is checking that leaving cleared
        // it, and the test would pass against a screen that never reset.
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

    // MARK: - Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Profile")
            SignuCard {
                VStack(spacing: 0) {
                    // The chevron promised a destination for four versions and had
                    // none: the row was an HStack, so the whole thing was inert
                    // (#4 from the production run). It is a Button now, and the
                    // destination is where the name and picture are changed (#7).
                    Button { actions.onEditProfile() } label: {
                        HStack(spacing: 14) {
                            ProfileAvatar(path: payload.avatarPath, initial: payload.initial, size: 46)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(payload.displayName)
                                    .font(.signuRowTitle)
                                    .foregroundStyle(SignuColor.textPrimary)
                                    .lineLimit(1)
                                // Invites the name rather than restating the address
                                // under itself, which is what this row did when
                                // `display_name` was null: two lines, one value.
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
                        // v32's lesson, and it applies to every row added since: a
                        // background does not extend a plain button's hit area, so
                        // the shape is declared.
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

    /// v19. Reuses 17d's send rather than rendering a form, because that is the
    /// only mechanism serving both identity states: a Google-only account has no
    /// current password to type, so an inline form would need two variants, one
    /// of them unverified. The email round-trip *is* the identity proof.
    @ViewBuilder
    private var passwordRow: some View {
        // Sent state replaces the row rather than sitting beside it: the action
        // is unavailable during the cooldown, and a live-looking row that
        // silently no-ops is the failure the countdown exists to prevent.
        if sentAt != nil {
            VStack(alignment: .leading, spacing: 2) {
                // No hedge, unlike 17d's "If an account exists for …". That
                // screen cannot confirm the address exists; here the session
                // proves it. The enumeration-safe doctrine tracks what the API
                // yields per surface, not one globally cautious phrasing.
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
                        // "Set" not "Change" for a Google-first account, the same
                        // distinction v11 made when naming 17d: there is no old
                        // password to change.
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
                // Without this the row's MIDDLE is dead to taps: a Spacer draws
                // nothing, so `.buttonStyle(.plain)` hit-tests only the text and the
                // chevron and the gap between them does nothing. Found by the UI
                // test, whose tap lands on the frame's centre — which is exactly
                // where a thumb aiming at a full-width row lands too.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// v19. Last row of Profile, and no confirmation: nothing is lost, the data
    /// is server-side, and signing back in is one tap. Sitting here rather than
    /// under Data keeps the whole scroll between it and Delete account — a
    /// benign, frequently-tapped row must not neighbour the most irreversible
    /// action in the app.
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
            // Same reason as the password row above. This one happened to pass its
            // UI test anyway, because the label is short enough that the tapped
            // centre still landed on the text — the defect was there regardless, for
            // every tap to the right of the word.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Connected banks (12a rows; 12d empty)

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
        // Flexible: text column takes remaining width, chip hugs content,
        // avatar fixed — so short subtitles ("Synced 2h ago · 2 cards") stay
        // one line at any width, long ones wrap to two.
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
        // As SignuRow: the row is the target. Bank rows are hand-built because
        // the right rail is a status chip rather than an amount.
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
        // A `.plain` button hit-tests only what it DRAWS, and this label ends in
        // a Spacer — so without this the middle of the row is dead and the row
        // reads as broken rather than as a narrow target. Safe here because
        // nothing inside it is itself tappable; rows with a nested button (the
        // dismissed row's Restore) must not get this without checking which of
        // the two wins.
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

    // MARK: - Dismissed suggestions

    private var dismissedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Dismissed suggestions")
            // One grouped card with hairline dividers (same as banks).
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

    // MARK: - Data

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
                // The card's fill does not make the row tappable — see
                // `tintedSurface`. This row is the most consequential one in the
                // app to have a dead middle.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bits

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
// In-shell: tab bar overlaid (short content keeps it visible, v13).
#Preview("Settings · in shell") { AppShellView(provider: MockDataProvider(), initialTab: .settings) }
