import SwiftUI

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

/// Auth screen scaffold: optional back chevron, large title + subtitle,
/// scrollable content, and a bottom-anchored action stack.
struct AuthScaffold<Content: View, Bottom: View>: View {
    var showBack = true
    var onBack: () -> Void = {}
    let title: String
    var subtitle: Text?
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

            VStack(spacing: 14) { bottom() }
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
        @State private var email = "marina.duarte@gmail.com"
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
