import SwiftUI

/// The one resend/reset cooldown in the app.
///
/// Supabase rate-limits the resend and reset endpoints at roughly 60s, so a
/// second tap inside that window fails *silently* — the API returns an error the
/// enumeration-safe surfaces deliberately swallow. The countdown is what makes
/// the limit visible, which is why the auth flow contract calls that error
/// "normally unreachable".
///
/// One constant because v19 put the same send behind a third surface (Settings →
/// Profile → password row). Three literal `120`s would drift, and the surface
/// that drifted low would be the one that fails quietly.
enum AuthCooldown {
    static let seconds = 120

    /// Seconds left on a cooldown that started at `sentAt`.
    ///
    /// Derived from a timestamp rather than counted down, because the surface that
    /// needs it most (v19's Settings row) is destroyed and rebuilt whenever the
    /// user changes tab — a counter would only tick while some view was alive to
    /// tick it, so two minutes on another tab would leave 100s still showing.
    ///
    /// Clamped at both ends. A clock that jumped backwards must not read as a
    /// longer cooldown than the one we set.
    static func remaining(since sentAt: Date?, now: Date) -> Int {
        guard let sentAt else { return 0 }
        return min(max(seconds - Int(now.timeIntervalSince(sentAt)), 0), seconds)
    }

    /// Whether a sent state should be forgotten as the user leaves the screen (v48).
    ///
    /// A function rather than an inline `cooldown == 0` so the rule can be pinned by
    /// tests: it decides how long a piece of UI keeps claiming something, and both
    /// of its clauses are easy to get subtly wrong. `remaining` clamps a backwards
    /// clock jump to the full window, so a device whose time moved back reads as
    /// "still cooling down" and the state survives — the safe direction, since the
    /// alternative is a Resend that no-ops inside Supabase's window.
    static func shouldForget(sentAt: Date?, now: Date) -> Bool {
        guard sentAt != nil else { return false }
        return remaining(since: sentAt, now: now) == 0
    }
}

/// Labeled input field for the auth screens (17a–17e). Ink border on focus,
/// hairline otherwise; optional reveal toggle for passwords.
struct AuthField: View {
    let label: String
    var placeholder = ""
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next

    @State private var reveal = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(SignuFont.font(15, .semibold))
                .foregroundStyle(SignuColor.textPrimary)
            HStack(spacing: 10) {
                Group {
                    if secure && !reveal {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(SignuFont.font(18))
                .foregroundStyle(SignuColor.textPrimary)
                .keyboardType(keyboard)
                .textInputAutocapitalization(secure || keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(submitLabel)

                if secure {
                    Button { reveal.toggle() } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye")
                            .font(.system(size: 18))
                            .foregroundStyle(SignuColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(SignuColor.surfaceBright, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(focused ? SignuColor.ink : SignuColor.hairline, lineWidth: focused ? 2 : 1)
            }
        }
    }
}


/// What an auth screen renders when an attempt fails.
///
/// A plain value, so the screens stay session-agnostic exactly as `WelcomeFlow`
/// promises: they never see `SessionAuthError`, and the mapping from error to copy
/// lives where the session already does.
struct AuthError {
    let message: String
    /// Present only when the failure has a remedy the user can tap. 17a's
    /// unconfirmed-email variant offers a resend; a wrong password does not.
    var actionTitle: String?
    var action: (() -> Void)?
}

/// The failure message, pinned above the action stack.
///
/// Placed there rather than in the scrolling content on purpose: a submit failure
/// has to sit next to the control that failed, and the content area can be
/// scrolled away or covered by the keyboard — which is exactly when someone is
/// most likely to have just mistyped a password.
struct AuthErrorBanner: View {
    let error: AuthError
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(SignuColor.red)
                    .font(.signuBody)
                Text(error.message)
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let title = error.actionTitle, let action = error.action {
                Button(title, action: action)
                    .font(.signuSubtitleEmphasis)
                    .foregroundStyle(SignuColor.textPrimary)
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SignuColor.redTint)
        )
        // One element to VoiceOver, so the message and its remedy are not two
        // unrelated stops.
        .accessibilityElement(children: .combine)
        .transition(reduceMotion ? .identity : .opacity)
    }
}

/// Auth screen scaffold: optional back chevron, large title + subtitle,
/// scrollable content, and a bottom-anchored action stack.
struct AuthScaffold<Content: View, Bottom: View>: View {
    var showBack = true
    var onBack: () -> Void = {}
    let title: String
    var subtitle: Text?
    /// Rendered above the action stack when an attempt fails. Deliberately NOT
    /// offered to 17d: `requestPasswordReset` succeeds unconditionally by
    /// contract (enumeration-safe), so a failure surface there would imply an
    /// outcome the flow refuses to report.
    var error: AuthError?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if showBack {
                        ChromeButton(systemName: "chevron.left", action: onBack)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.signuScreenTitle)
                            .foregroundStyle(SignuColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        subtitle?
                            .font(.signuBody)
                            .foregroundStyle(SignuColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content()
                }
                .padding(.horizontal, SignuMetric.screenPadding)
                .padding(.top, 4)
                .padding(.bottom, 170)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 14) {
                if let error { AuthErrorBanner(error: error) }
                bottom()
            }
            .animation(.easeInOut(duration: 0.2), value: error != nil)
                .padding(.horizontal, SignuMetric.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(SignuColor.paper.ignoresSafeArea())
        }
        .background(SignuColor.paper)
    }
}

/// The password policy hint — identical copy on 17b and 17e (contract).
struct PasswordHint: View {
    var body: some View {
        Text("At least 8 characters, with 1 uppercase letter and 1 number.")
            .font(SignuFont.font(14))
            .foregroundStyle(SignuColor.textSecondary)
    }
}

/// "By continuing you agree to our Terms and Privacy Policy." — clickwrap
/// line, present on Welcome and Create account only.
struct TermsLine: View {
    var body: some View {
        (
            Text("By continuing you agree to our ")
                .foregroundStyle(SignuColor.textSecondary)
            + Text("Terms").underline().foregroundStyle(SignuColor.textPrimary)
            + Text(" and ").foregroundStyle(SignuColor.textSecondary)
            + Text("Privacy Policy").underline().foregroundStyle(SignuColor.textPrimary)
            + Text(".").foregroundStyle(SignuColor.textSecondary)
        )
        .font(.signuSubtitle)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Simplified multicolor Google "G" for the OAuth button. A production build
/// bundles the official asset; this is a recognizable stand-in.
struct GoogleGLogo: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().trim(from: 0.0, to: 0.25).stroke(Color(hex: 0xEA4335), lineWidth: size * 0.22).rotationEffect(.degrees(-45))
            Circle().trim(from: 0.25, to: 0.5).stroke(Color(hex: 0xFBBC05), lineWidth: size * 0.22).rotationEffect(.degrees(-45))
            Circle().trim(from: 0.5, to: 0.75).stroke(Color(hex: 0x34A853), lineWidth: size * 0.22).rotationEffect(.degrees(-45))
            Circle().trim(from: 0.75, to: 1.0).stroke(Color(hex: 0x4285F4), lineWidth: size * 0.22).rotationEffect(.degrees(-45))
            // Crossbar of the G.
            Rectangle().fill(Color(hex: 0x4285F4))
                .frame(width: size * 0.42, height: size * 0.22)
                .offset(x: size * 0.24, y: 0)
        }
        .frame(width: size, height: size)
        .clipShape(Rectangle().offset(x: 0))
    }
}

#Preview("Auth field") {
    struct Host: View {
        @State private var email = "marina.duarte@example.com"
        @State private var pass = "Secret123"
        var body: some View {
            VStack(spacing: 20) {
                AuthField(label: "Email", placeholder: "you@email.com", text: $email, keyboard: .emailAddress)
                AuthField(label: "Password", placeholder: "Password", text: $pass, secure: true)
                PasswordHint()
                HStack { GoogleGLogo(); Text("Continue with Google") }
                TermsLine()
            }
            .padding()
            .background(SignuColor.paper)
        }
    }
    return Host()
}
