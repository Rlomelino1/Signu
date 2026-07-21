import SwiftUI

// UI-only auth screens (17a–17e). Actions are stubs; no backend.

// MARK: - Sign in (17a)

struct SignInView: View {
    var onBack: () -> Void = {}
    var onForgot: () -> Void = {}
    var onSubmit: () -> Void = {}

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        AuthScaffold(
            onBack: onBack,
            title: "Welcome back",
            subtitle: Text("Sign in to pick up where you left off.")
        ) {
            VStack(alignment: .leading, spacing: 16) {
                AuthField(label: "Email", placeholder: "you@email.com", text: $email, keyboard: .emailAddress)
                AuthField(label: "Password", placeholder: "Password", text: $password, secure: true, submitLabel: .go)
                Button("Forgot password?", action: onForgot)
                    .font(.signuSubtitleEmphasis)
                    .foregroundStyle(SignuColor.textPrimary)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } bottom: {
            Button("Sign in", action: onSubmit).buttonStyle(.signuPrimary)
        }
    }
}

// MARK: - Create account (17b)

struct CreateAccountView: View {
    var onBack: () -> Void = {}
    var onSubmit: (String) -> Void = { _ in }   // passes the entered email → 17c

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        AuthScaffold(
            onBack: onBack,
            title: "Create your account",
            subtitle: Text("A few seconds now, no forgotten renewals later.")
        ) {
            VStack(alignment: .leading, spacing: 16) {
                AuthField(label: "Name", placeholder: "Your name", text: $name)
                AuthField(label: "Email", placeholder: "you@email.com", text: $email, keyboard: .emailAddress)
                AuthField(label: "Password", placeholder: "Password", text: $password, secure: true, submitLabel: .done)
                PasswordHint()
            }
        } bottom: {
            Button("Create account") { onSubmit(email.isEmpty ? "you@email.com" : email) }
                .buttonStyle(.signuPrimary)
            TermsLine()
        }
    }
}

// MARK: - Confirm email (17c)

struct ConfirmEmailView: View {
    let email: String
    var onConfirmed: () -> Void = {}
    var onResend: () -> Void = {}
    var onGoBack: () -> Void = {}

    // 120s resend cooldown (clears Supabase's ~60s rate limit).
    @State private var cooldown = 0
    @State private var notConfirmed = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 16) {
                Spacer()
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(SignuColor.surfaceBright)
                    .frame(width: 96, height: 96)
                    .overlay { Image(systemName: "envelope").font(.system(size: 34)).foregroundStyle(SignuColor.textPrimary) }
                Text("Check your inbox")
                    .font(.signuScreenTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                VStack(spacing: 2) {
                    Text("We sent a confirmation link to")
                        .foregroundStyle(SignuColor.textSecondary)
                    Text(email).fontWeight(.semibold).foregroundStyle(SignuColor.textPrimary)
                }
                .font(.signuBody)
                .multilineTextAlignment(.center)
                Text("Tap the link in the email and we'll take you straight in.")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if notConfirmed {
                    Text("Not confirmed yet — check your inbox.")
                        .font(.signuSubtitleEmphasis)
                        .foregroundStyle(SignuColor.gold)
                }
                Spacer()
                Spacer()
            }
            .padding(.horizontal, SignuMetric.screenPadding)
            .frame(maxWidth: .infinity)

            VStack(spacing: 14) {
                Button("I've confirmed my email") { notConfirmed = true }
                    .buttonStyle(.signuPrimary)
                // Resend shows a 120s countdown once tapped, then reactivates.
                if cooldown > 0 {
                    Text("Resend available in \(cooldown)s")
                        .font(.signuSubtitle)
                        .foregroundStyle(SignuColor.textSecondary)
                } else {
                    Button {
                        cooldown = 120
                        onResend()
                    } label: {
                        (
                            Text("Didn't get it? ").foregroundStyle(SignuColor.textSecondary)
                            + Text("Resend email").foregroundStyle(SignuColor.textPrimary).bold()
                        ).font(.signuBody)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onGoBack) {
                    (
                        Text("Wrong address? ").foregroundStyle(SignuColor.textSecondary)
                        + Text("Go back").underline().foregroundStyle(SignuColor.textPrimary)
                    ).font(.signuSubtitle)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, SignuMetric.screenPadding)
            .padding(.bottom, 8)
        }
        .background(SignuColor.paper)
        .onReceive(tick) { _ in if cooldown > 0 { cooldown -= 1 } }
    }
}

// MARK: - Forgot / set password (17d)

struct ForgotPasswordView: View {
    var onBack: () -> Void = {}

    @State private var email = ""
    @State private var sent = false
    @State private var cooldown = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        AuthScaffold(
            onBack: onBack,
            title: "Reset your password",
            subtitle: Text("Enter your email and we'll send you a link to set a new one.")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                AuthField(label: "Email", placeholder: "you@email.com", text: $email, keyboard: .emailAddress, submitLabel: .send)
                if sent {
                    // Enumeration-safe: never claims a send happened.
                    Text("If an account exists for \(email.isEmpty ? "that address" : email), a link is on its way.")
                        .font(.signuSubtitle)
                        .foregroundStyle(SignuColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } bottom: {
            if cooldown > 0 {
                Text("Resend available in \(cooldown)s")
                    .font(.signuButton)
                    .foregroundStyle(SignuColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: SignuMetric.buttonHeight)
            } else {
                Button("Send reset link") {
                    sent = true
                    cooldown = 120
                }
                .buttonStyle(.signuPrimary)
            }
        }
        .onReceive(tick) { _ in if cooldown > 0 { cooldown -= 1 } }
    }
}

// MARK: - Choose new password (17e) — deep-link destination, no back chevron

struct NewPasswordView: View {
    let email: String
    var onSubmit: () -> Void = {}

    @State private var password = ""
    @State private var confirm = ""

    var body: some View {
        AuthScaffold(
            showBack: false,
            title: "Choose a new password",
            subtitle: Text("You're signed in as ") + Text(email).fontWeight(.semibold).foregroundColor(SignuColor.textPrimary) + Text(".")
        ) {
            VStack(alignment: .leading, spacing: 16) {
                AuthField(label: "New password", placeholder: "Password", text: $password, secure: true)
                PasswordHint()
                AuthField(label: "Confirm new password", placeholder: "Repeat password", text: $confirm, secure: true, submitLabel: .done)
            }
        } bottom: {
            Button("Set new password", action: onSubmit).buttonStyle(.signuPrimary)
        }
    }
}

#Preview("Sign in (17a)") { SignInView() }
#Preview("Create account (17b)") { CreateAccountView() }
#Preview("Confirm email (17c)") { ConfirmEmailView(email: "marina.duarte@gmail.com") }
#Preview("Forgot password (17d)") { ForgotPasswordView() }
#Preview("New password (17e)") { NewPasswordView(email: "marina.duarte@gmail.com") }
