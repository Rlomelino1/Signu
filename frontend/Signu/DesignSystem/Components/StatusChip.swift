import SwiftUI

struct StatusChip: View {
    enum Tone {
        case positive
        case warning
        case danger
        case neutral
    }

    let text: String
    var tone: Tone
    var onInk = false
    var compact = false

    var body: some View {
        Text(text)
            .font(.signuChip)
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, compact ? 3 : 6)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch (tone, onInk) {
        case (.positive, true): SignuColor.greenOnInk
        case (.positive, false): SignuColor.green
        case (.warning, _): SignuColor.gold
        case (.danger, true): SignuColor.redOnInk
        case (.danger, false): SignuColor.red
        case (.neutral, true): SignuColor.onInkSecondary
        case (.neutral, false): SignuColor.textSecondary
        }
    }

    private var background: Color {
        if onInk { return foreground.opacity(0.16) }
        switch tone {
        case .positive: return SignuColor.greenTint
        case .warning: return SignuColor.goldTint
        case .danger: return SignuColor.redTint
        case .neutral: return SignuColor.sunken
        }
    }
}

#Preview("Chips on light") {
    VStack(spacing: 12) {
        HStack {
            StatusChip(text: "Active", tone: .positive)
            StatusChip(text: "Ended", tone: .neutral)
            StatusChip(text: "Cancelled", tone: .danger)
        }
        HStack {
            StatusChip(text: "Needs action", tone: .danger)
            StatusChip(text: "Expiring", tone: .warning)
        }
        HStack {
            StatusChip(text: "FOUND", tone: .positive)
            StatusChip(text: "PRICE RAISED", tone: .warning)
        }
    }
    .padding()
    .background(SignuColor.paper)
}

#Preview("Chips on ink") {
    HStack {
        StatusChip(text: "Active", tone: .positive, onInk: true)
        StatusChip(text: "Overdue", tone: .danger, onInk: true)
        StatusChip(text: "Ended", tone: .neutral, onInk: true)
    }
    .padding(24)
    .background(SignuColor.ink)
}
