import SwiftUI

// The auth screens (17a–17e). Layout and copy are locked; the actions are
// wired to a `SessionStore` by their host (`WelcomeFlow`, or the gate itself
// for 17e). No screen here touches a session directly.

// MARK: - Sign in (17a)

struct SignInView: View {
    var onBack: () -> Void = {}
    var onForgot: () -> Void = {}
    var onSubmit: (String, String) -> Void = { _, _ in }   // email, password
    /// Populated by `WelcomeFlow` from `SessionStore.lastError`. Until this
    /// existed the store recorded every failure and nothing read it, so a wrong
    /// password looked identical to a button that did nothing.
    var error: AuthError?

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        AuthScaffold(
            onBack: onBack,
            title: "Welcome back",
            subtitle: Text("Sign in to pick up where you left off."),
            error: error
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
            Button("Sign in") { onSubmit(email, password) }
                .buttonStyle(.signuPrimary)
        }
    }
}

// MARK: - Create account (17b)

struct CreateAccountView: View {
    var onBack: () -> Void = {}
    /// name, email, password. Signup never yields a session (confirmation is
    /// ON), so the host always pushes 17c after this — there is no
    /// "maybe signed in" outcome to handle.
    var onSubmit: (String, String, String) -> Void = { _, _, _ in }
    var error: AuthError?

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        AuthScaffold(
            onBack: onBack,
            title: "Create your account",
            subtitle: Text("A few seconds now, no forgotten renewals later."),
            error: error
        ) {
            VStack(alignment: .leading, spacing: 16) {
                AuthField(label: "Name", placeholder: "Your name", text: $name)
                AuthField(label: "Email", placeholder: "you@email.com", text: $email, keyboard: .emailAddress)
                AuthField(label: "Password", placeholder: "Password", text: $password, secure: true, submitLabel: .done)
                PasswordHint()
            }
        } bottom: {
            Button("Create account") { onSubmit(name, email, password) }
                .buttonStyle(.signuPrimary)
            TermsLine()
        }
    }
}

// MARK: - Confirm email (17c)

struct ConfirmEmailView: View {
    // No error slot, deliberately. 17c does not use AuthScaffold, and its only
    // failure -- a resend inside the rate limit -- is already prevented by the
    // cooldown rendered below, which is why the contract calls that error
    // "normally unreachable". A second, differently-placed error surface here
    // would be inconsistent without being useful.
    let email: String
    /// The manual check (`getUser()` behind the store) for the wrong-device
    /// case — the link was opened on a laptop, so the deep link fired
    /// elsewhere or nowhere. true means confirmation landed and the gate has
    /// already swapped the root away from this screen; false renders the
    /// inline "Not confirmed yet" line below.
    var onCheck: () async -> Bool = { false }
    var onResend: () -> Void = {}
    var onGoBack: () -> Void = {}

    // Resend cooldown, clearing Supabase's ~60s rate limit. See AuthCooldown.
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
                Button("I've confirmed my email") {
                    Task {
                        let confirmed = await onCheck()
                        notConfirmed = !confirmed
                    }
                }
                .buttonStyle(.signuPrimary)
                // Resend shows the countdown once tapped, then reactivates.
                if cooldown > 0 {
                    Text("Resend available in \(cooldown)s")
                        .font(.signuSubtitle)
                        .foregroundStyle(SignuColor.textSecondary)
                } else {
                    Button {
                        cooldown = AuthCooldown.seconds
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
    /// Set when an expired/invalid recovery link routed the user here. The
    /// contract requires the notice ("never a silent dead end"); it renders in
    /// the same slot as the enumeration-safe sent line below.
    var showExpiredLinkNotice = false
    var onBack: () -> Void = {}
    var onSend: (String) -> Void = { _ in }

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
                } else if showExpiredLinkNotice {
                    // Reset links expire (~1h); the deep-link handler routes
                    // failures back here. Copy paraphrases the contract's
                    // prose — no exact string is locked and no mockup shows
                    // this state (see the PR note).
                    Text("That link expired — request a new one.")
                        .font(.signuSubtitle)
                        .foregroundStyle(SignuColor.gold)
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
                    cooldown = AuthCooldown.seconds
                    onSend(email)
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
    /// The new password. Success is what ends `.recovering` — until then the
    /// session is live but the password is still the old one.
    var onSubmit: (String) -> Void = { _ in }
    var error: AuthError?

    @State private var password = ""
    @State private var confirm = ""

    var body: some View {
        AuthScaffold(
            showBack: false,
            title: "Choose a new password",
            subtitle: Text("You're signed in as ") + Text(email).fontWeight(.semibold).foregroundColor(SignuColor.textPrimary) + Text("."),
            error: error
        ) {
            VStack(alignment: .leading, spacing: 16) {
                AuthField(label: "New password", placeholder: "Password", text: $password, secure: true)
                PasswordHint()
                AuthField(label: "Confirm new password", placeholder: "Repeat password", text: $confirm, secure: true, submitLabel: .done)
            }
        } bottom: {
            Button("Set new password") { onSubmit(password) }
                .buttonStyle(.signuPrimary)
        }
    }
}

#Preview("Sign in (17a)") { SignInView() }
#Preview("Create account (17b)") { CreateAccountView() }
#Preview("Confirm email (17c)") { ConfirmEmailView(email: "marina.duarte@example.com") }
#Preview("Forgot password (17d)") { ForgotPasswordView() }
#Preview("Forgot password · expired link (17d)") { ForgotPasswordView(showExpiredLinkNotice: true) }
#Preview("New password (17e)") { NewPasswordView(email: "marina.duarte@example.com") }

// Failure states. The store has always recorded these; until the scaffold gained
// an error slot nothing could render them, so there was nothing to review. Copy
// comes from SessionAuthError.signInMessage so a preview cannot drift from what
// the app shows.
#Preview("Sign in · wrong password (17a)") {
    SignInView(error: AuthError(message: SessionAuthError.invalidCredentials.signInMessage))
}
#Preview("Sign in · email not confirmed (17a)") {
    SignInView(error: AuthError(
        message: SessionAuthError.emailNotConfirmed.signInMessage,
        actionTitle: "Resend confirmation email",
        action: {}
    ))
}
#Preview("Create account · failed (17b)") {
    CreateAccountView(error: AuthError(message: SessionAuthError.invalidCredentials.signInMessage))
}
#Preview("New password · failed (17e)") {
    NewPasswordView(
        email: "marina.duarte@example.com",
        error: AuthError(message: "Couldn't set your new password. Try again.")
    )
}
