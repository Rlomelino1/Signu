import SwiftUI

enum AuthCooldown {
    static let seconds = 120

    static func remaining(since sentAt: Date?, now: Date) -> Int {
        guard let sentAt else { return 0 }
        return min(max(seconds - Int(now.timeIntervalSince(sentAt)), 0), seconds)
    }

    static func shouldForget(sentAt: Date?, now: Date) -> Bool {
        guard sentAt != nil else { return false }
        return remaining(since: sentAt, now: now) == 0
    }
}

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


struct AuthError {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
}

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
        .accessibilityElement(children: .combine)
        .transition(reduceMotion ? .identity : .opacity)
    }
}

struct AuthScaffold<Content: View, Bottom: View>: View {
    var showBack = true
    var onBack: () -> Void = {}
    let title: String
    var subtitle: Text?
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

struct PasswordHint: View {
    var body: some View {
        Text("At least 8 characters, with 1 uppercase letter and 1 number.")
            .font(SignuFont.font(14))
            .foregroundStyle(SignuColor.textSecondary)
    }
}

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

struct GoogleGLogo: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().trim(from: 0.0, to: 0.25).stroke(Color(hex: 0xEA4335), lineWidth: size * 0.22).rotationEffect(.degrees(-45))
            Circle().trim(from: 0.25, to: 0.5).stroke(Color(hex: 0xFBBC05), lineWidth: size * 0.22).rotationEffect(.degrees(-45))
            Circle().trim(from: 0.5, to: 0.75).stroke(Color(hex: 0x34A853), lineWidth: size * 0.22).rotationEffect(.degrees(-45))
            Circle().trim(from: 0.75, to: 1.0).stroke(Color(hex: 0x4285F4), lineWidth: size * 0.22).rotationEffect(.degrees(-45))
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
                AuthField(label: "Email", placeholder: "you@example.test", text: $email, keyboard: .emailAddress)
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
