import SwiftUI

#if DEBUG
/// One-stop preview of the design system — tokens and every reusable
/// component, on paper. Not part of any navigation flow.
struct DesignSystemGallery: View {
    var anchor: UnitPoint = .top
    @State private var sort = 0
    @State private var tab = SignuTab.home

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                group("Type scale") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("R$ 246,40").font(.signuHeroXL)
                        Text("Subscriptions").font(.signuScreenTitle)
                        Text("Good afternoon, Rafa").font(.signuTitle)
                        Text("Coming up").font(.signuSection)
                        Text("Row title / amount").font(.signuRowTitle)
                        Text("Body copy for explainer paragraphs.").font(.signuBody)
                        Text("Row subtitle · Monthly · Visa 4821").font(.signuSubtitle)
                            .foregroundStyle(SignuColor.textSecondary)
                        OverlineText("This month")
                    }
                    .foregroundStyle(SignuColor.textPrimary)
                }

                group("Currency & tilde") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(SignuFormat.brl(Decimal(string: "3405.70")!) + " /yr")
                        Text(SignuFormat.brl(Decimal(string: "283.81")!, approximate: true) + " /mo")
                        Text("Empty state: \(SignuFormat.dash)")
                    }
                    .font(.signuRowTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                }

                group("Chips") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            StatusChip(text: "Active", tone: .positive)
                            StatusChip(text: "Ended", tone: .neutral)
                            StatusChip(text: "Cancelled", tone: .danger)
                        }
                        HStack {
                            StatusChip(text: "Needs action", tone: .danger)
                            StatusChip(text: "Expiring", tone: .warning)
                            StatusChip(text: "FOUND", tone: .positive)
                        }
                    }
                }

                group("Avatars") {
                    HStack(spacing: 10) {
                        ServiceAvatar(name: "Netflix")
                        ServiceAvatar(name: "Spotify")
                        ServiceAvatar(name: "Globoplay")
                        ServiceAvatar(name: "iCloud+")
                        ServiceAvatar(name: "Smart Fit")
                        ServiceAvatar(name: "Duolingo Super")
                    }
                }

                group("Ink hero — run states") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(SubscriptionHeroCard.previewStates.indices, id: \.self) { index in
                            let state = SubscriptionHeroCard.previewStates[index]
                            VStack(alignment: .leading, spacing: 6) {
                                Text(state.title)
                                    .font(.signuCaption)
                                    .foregroundStyle(SignuColor.textTertiary)
                                state.card
                            }
                        }
                    }
                }

                group("Rows") {
                    SignuListCard(data: sampleRows) { row in
                        SignuRow(
                            title: row.name,
                            subtitle: Text(row.sub).foregroundStyle(row.alert ? SignuColor.red : SignuColor.textSecondary),
                            trailingTitle: Text(row.amount),
                            trailingSubtitle: Text(row.date)
                        ) {
                            ServiceAvatar(name: row.name)
                        }
                    }
                }

                group("Controls") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            FilterChip(label: "All", count: 10, isSelected: true)
                            FilterChip(label: "Active", count: 8)
                            FilterChip(label: "Inactive", count: 2)
                        }
                        SortToggle(options: ["By date", "By cost"], selection: $sort)
                        HStack(spacing: 10) {
                            DateBadge(date: MockDataProvider.date(2026, 7, 15))
                            DateBadge(date: MockDataProvider.date(2026, 7, 10), overdue: true)
                            ChromeButton(systemName: "chevron.left")
                            ChromeButton(systemName: "ellipsis")
                        }
                        WarningBanner(text: "Nubank connection needs attention", actionLabel: "Fix")
                    }
                }

                group("Buttons") {
                    VStack(spacing: 12) {
                        Button("Create account") {}.buttonStyle(.signuPrimary)
                        HStack(spacing: 12) {
                            Button("Track it") {}.buttonStyle(.signuSuccess)
                            Button("Not a subscription") {}.buttonStyle(.signuSecondary)
                        }
                        Button("Mark cancelled") {}.buttonStyle(.signuDestructiveOutline)
                        Button("Remove link, keep history") {}.buttonStyle(.signuDestructiveFilled)
                    }
                }

                group("Tab bar") {
                    HStack {
                        Spacer()
                        SignuTabBar(selection: $tab)
                        Spacer()
                    }
                }
            }
            .padding(SignuMetric.screenPadding)
        }
        .defaultScrollAnchor(anchor)
        .background(SignuColor.paper)
    }

    private struct GalleryRow: Identifiable {
        let id = UUID()
        let name: String
        let sub: String
        let amount: String
        let date: String
        var alert = false
    }

    private var sampleRows: [GalleryRow] {
        [
            GalleryRow(name: "Globoplay", sub: "Overdue · 3 days", amount: "R$ 24,90", date: "Jul 10", alert: true),
            GalleryRow(name: "Spotify", sub: "Monthly · Master 7730", amount: "R$ 21,90", date: "Jul 15"),
            GalleryRow(name: "Netflix", sub: "Monthly · Visa 4821", amount: "R$ 44,90", date: "Jul 18"),
        ]
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title)
            content()
        }
    }
}

#Preview("Design system") {
    DesignSystemGallery()
}
#endif
