import SwiftUI

/// Section header: uppercase overline, optional trailing accessory.
struct SectionHeader<Trailing: View>: View {
    let text: String
    var color: Color = SignuColor.textSecondary
    @ViewBuilder var trailing: Trailing

    init(_ text: String, color: Color = SignuColor.textSecondary, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.text = text
        self.color = color
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            OverlineText(text, color: color)
            Spacer()
            trailing
        }
    }
}

/// Calendar date badge on home rows — "JUL" over "15".
struct DateBadge: View {
    let date: Date
    var overdue = false

    var body: some View {
        VStack(spacing: 0) {
            Text(SignuFormat.monthAbbrev(date).uppercased())
                .font(SignuFont.font(11, .semibold))
                .kerning(0.5)
                .foregroundStyle(overdue ? SignuColor.red : SignuColor.textSecondary)
            Text(SignuFormat.dayNumber(date))
                .font(SignuFont.font(20, .bold, tabular: true))
                .foregroundStyle(overdue ? SignuColor.red : SignuColor.textPrimary)
        }
        .frame(width: 48, height: 48)
        .background(
            overdue ? SignuColor.red.opacity(0.1) : SignuColor.sunken.opacity(0.7),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

/// Filter chip — "All · 10" / "Active · 8" / "Inactive · 2".
struct FilterChip: View {
    let label: String
    var count: Int?
    var isSelected = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(count.map { "\(label) · \($0)" } ?? label)
                .font(SignuFont.font(16, .semibold, tabular: true))
                .foregroundStyle(isSelected ? SignuColor.onInk : SignuColor.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? SignuColor.ink : SignuColor.surface, in: Capsule())
                .overlay {
                    if !isSelected {
                        Capsule().strokeBorder(SignuColor.hairline, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// Two-segment sort toggle — "By date | By cost".
struct SortToggle: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    Text(options[index])
                        .font(.signuChip)
                        .foregroundStyle(index == selection ? SignuColor.textPrimary : SignuColor.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if index == selection {
                                Capsule().fill(SignuColor.surface)
                                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(SignuColor.sunken.opacity(0.7), in: Capsule())
    }
}

/// Warning banner — the home connection-problem slot ("plumbing problems"
/// severity channel; overdue never renders here).
struct WarningBanner: View {
    let text: String
    var actionLabel: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(SignuFont.font(16, .semibold, tabular: true))
            Text(text)
                .font(.signuSubtitleEmphasis)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionLabel {
                Button(actionLabel, action: action)
                    .font(.signuSubtitleEmphasis)
            }
        }
        .foregroundStyle(SignuColor.gold)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(SignuColor.goldTint, in: RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous))
    }
}

/// Round floating chrome button — back chevron, ellipsis.
struct ChromeButton: View {
    let systemName: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SignuColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(SignuColor.surface, in: Circle())
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Small components") {
    struct Host: View {
        @State private var sort = 0
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Connected banks")
                HStack(spacing: 10) {
                    DateBadge(date: .now)
                    DateBadge(date: .now, overdue: true)
                    ChromeButton(systemName: "chevron.left")
                    ChromeButton(systemName: "ellipsis")
                }
                HStack(spacing: 8) {
                    FilterChip(label: "All", count: 10, isSelected: true)
                    FilterChip(label: "Active", count: 8)
                    FilterChip(label: "Inactive", count: 2)
                }
                SortToggle(options: ["By date", "By cost"], selection: $sort)
                WarningBanner(text: "Nubank connection needs attention", actionLabel: "Fix")
            }
            .padding(SignuMetric.screenPadding)
            .background(SignuColor.paper)
        }
    }
    return Host()
}
