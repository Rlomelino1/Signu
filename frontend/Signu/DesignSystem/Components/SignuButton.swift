import SwiftUI

/// Capsule button styles from the mockups.
struct SignuButtonStyle: ButtonStyle {
    enum Kind {
        case primary            // ink fill, paper text (Create account, Sign in)
        case secondary          // light surface, hairline stroke (Continue with Google, Not a subscription)
        case success            // sage fill (Track it)
        case destructiveOutline // light surface, red text (Mark cancelled, Remove this bank link)
        case destructiveFilled  // brick fill (Remove link…, Delete my account)
        case onInk              // translucent light on the ink hero (Reconnect)
    }

    var kind: Kind = .primary
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.signuButton)
            .foregroundStyle(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: SignuMetric.buttonHeight)
            .padding(.horizontal, fullWidth ? 0 : 28)
            .background(background, in: Capsule())
            .overlay {
                if hasStroke {
                    Capsule().strokeBorder(strokeColor, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: SignuColor.onInk
        case .secondary: SignuColor.textPrimary
        case .success: .white
        case .destructiveOutline: SignuColor.red
        case .destructiveFilled: .white
        case .onInk: SignuColor.onInk
        }
    }

    private var background: Color {
        switch kind {
        case .primary: SignuColor.ink
        case .secondary: SignuColor.surface
        case .success: SignuColor.greenFill
        case .destructiveOutline: SignuColor.surface
        case .destructiveFilled: SignuColor.redFill
        case .onInk: Color.white.opacity(0.12)
        }
    }

    private var hasStroke: Bool {
        kind == .secondary || kind == .destructiveOutline
    }

    private var strokeColor: Color {
        kind == .destructiveOutline ? SignuColor.redTint : SignuColor.hairline
    }
}

extension ButtonStyle where Self == SignuButtonStyle {
    static var signuPrimary: SignuButtonStyle { .init(kind: .primary) }
    static var signuSecondary: SignuButtonStyle { .init(kind: .secondary) }
    static var signuSuccess: SignuButtonStyle { .init(kind: .success) }
    static var signuDestructiveOutline: SignuButtonStyle { .init(kind: .destructiveOutline) }
    static var signuDestructiveFilled: SignuButtonStyle { .init(kind: .destructiveFilled) }
    static var signuOnInk: SignuButtonStyle { .init(kind: .onInk) }
}

#Preview("Buttons") {
    VStack(spacing: 14) {
        Button("Create account") {}.buttonStyle(.signuPrimary)
        Button("Continue with Google") {}.buttonStyle(.signuSecondary)
        HStack(spacing: 12) {
            Button("Track it") {}.buttonStyle(SignuButtonStyle(kind: .success))
            Button("Not a subscription") {}.buttonStyle(.signuSecondary)
        }
        Button("Mark cancelled") {}.buttonStyle(.signuDestructiveOutline)
        Button("Remove link, keep history") {}.buttonStyle(.signuDestructiveFilled)
        Button("Reconnect Itaú") {}
            .buttonStyle(.signuOnInk)
            .padding(16)
            .background(SignuColor.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .padding(SignuMetric.screenPadding)
    .background(SignuColor.paper)
}
