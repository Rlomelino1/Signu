import SwiftUI

/// Loads the home payload from the provider and renders it.
struct HomeScreen: View {
    let provider: SignuDataProviding
    var actions = HomeActions()
    var scrollAnchor: UnitPoint = .top

    @State private var payload: HomePayload?

    var body: some View {
        Group {
            if let payload {
                HomeView(payload: payload, actions: actions, scrollAnchor: scrollAnchor)
            } else {
                Color.clear
            }
        }
        .task {
            payload = try? await provider.homePayload()
        }
    }
}

/// Navigation hooks — wired up as their destinations land (banner → 12b,
/// review → 9a, subscription → detail).
struct HomeActions {
    var onFixConnection: (UUID) -> Void = { _ in }
    var onReview: () -> Void = {}
    var onCalendar: () -> Void = {}
    var onSeeAll: () -> Void = {}
    var onSelectSubscription: (UUID) -> Void = { _ in }
    var onConnectBank: () -> Void = {}
}

/// Stateless render of a HomePayload (21g / 21h / 21i).
struct HomeView: View {
    let payload: HomePayload
    var actions = HomeActions()
    var scrollAnchor: UnitPoint = .top

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let banner = payload.banner {
                    WarningBanner(text: banner.text, actionLabel: "Fix") {
                        actions.onFixConnection(banner.connectionId)
                    }
                }

                // Label sits tight above the number, caption-style (21i).
                VStack(alignment: .leading, spacing: 5) {
                    OverlineText("This month")
                        .padding(.top, 2)

                    switch payload.content {
                    case .noBank:
                        noBankContent
                    case .watching(let syncText):
                        watchingContent(syncText: syncText)
                    case .active(let active):
                        activeContent(active)
                    }
                }
            }
            .padding(.horizontal, SignuMetric.screenPadding)
            .padding(.bottom, SignuMetric.scrollBottomInset)
        }
        .defaultScrollAnchor(scrollAnchor)
        .background(SignuColor.paper)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                OverlineText(SignuFormat.weekdayFull(payload.now))
                Text("\(greeting), \(payload.firstName)")
                    .font(.signuTitle)
                    .foregroundStyle(SignuColor.textPrimary)
            }
            Spacer()
            Circle()
                .fill(SignuColor.ink)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(payload.firstName.prefix(1)).uppercased())
                        .font(SignuFont.font(18, .semibold))
                        .foregroundStyle(SignuColor.onInk)
                }
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        let hour = MockDataProvider.calendar.component(.hour, from: payload.now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - No bank (21g)

    private var noBankContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Capsule()
                    .fill(SignuColor.sunken)
                    .frame(width: 64, height: 10)
                Text("Connect a bank to start tracking")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
            }

            SignuCard {
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(SignuColor.sunken.opacity(0.7))
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(systemName: "building.columns")
                                .font(.system(size: 24))
                                .foregroundStyle(SignuColor.textPrimary)
                        }
                    Text("Connect your first bank")
                        .font(.signuSection)
                        .foregroundStyle(SignuColor.textPrimary)
                    Text("We read your card transactions and find the recurring charges. Read-only, via Open Finance — we can never move money.")
                        .font(.signuBody)
                        .foregroundStyle(SignuColor.textSecondary)
                    Button("Connect a bank", action: actions.onConnectBank)
                        .buttonStyle(.signuPrimary)
                        .padding(.top, 6)
                }
                .padding(20)
            }

            comingUpHeader(showCalendar: false)
                .padding(.top, 8)
            EmptyDashCard(
                title: "Your renewals will appear here",
                subtitle: "with dates and amounts, a few days ahead"
            )
        }
    }

    // MARK: - Watching (21h)

    private func watchingContent(syncText: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("No subscriptions detected yet")
                    .font(SignuFont.font(20))
                    .foregroundStyle(SignuColor.textSecondary)
                syncRow(syncText)
            }

            SignuCard(background: SignuColor.greenTint) {
                HStack(alignment: .top, spacing: 14) {
                    Circle()
                        .fill(SignuColor.green)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("We're watching for patterns")
                            .font(SignuFont.font(18, .semibold))
                            .foregroundStyle(SignuColor.green)
                        Text("Most subscriptions confirm after their second charge — usually within a month. Known services like Netflix can appear sooner.")
                            .font(.signuBody)
                            .foregroundStyle(SignuColor.green.opacity(0.85))
                    }
                }
                .padding(18)
            }

            comingUpHeader(showCalendar: false)
                .padding(.top, 8)
            EmptyDashCard(
                title: "Nothing to predict yet",
                subtitle: "renewal dates appear once a subscription is confirmed"
            )
        }
    }

    // MARK: - Active (21i)

    private func activeContent(_ active: HomePayload.Active) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(SignuFormat.brl(active.monthToDateTotal))
                    .font(.signuHeroXL)
                    .foregroundStyle(SignuColor.textPrimary)
                statusLine(active)
                syncRow(active.syncText)
            }

            ForEach(active.overdue) { item in
                overdueRow(item)
            }

            comingUpHeader(showCalendar: true)
                .padding(.top, 4)
            if active.comingUp.isEmpty {
                EmptyDashCard(
                    title: "Nothing in the next two weeks",
                    subtitle: "renewals appear here a few days ahead"
                )
            } else {
                SignuListCard(data: active.comingUp) { item in
                    comingUpRow(item)
                }
            }

            if active.suggestionCount > 0 {
                reviewPill(count: active.suggestionCount)
            }

            HStack {
                Text("Your subscriptions")
                    .font(.signuSection)
                    .foregroundStyle(SignuColor.textPrimary)
                Spacer()
                Button("See all", action: actions.onSeeAll)
                    .font(.signuSubtitleEmphasis)
                    .foregroundStyle(SignuColor.textPrimary)
                    .buttonStyle(.plain)
            }
            .padding(.top, 4)

            SignuListCard(data: active.subscriptions) { item in
                subscriptionRow(item)
            }
        }
    }

    private func statusLine(_ active: HomePayload.Active) -> Text {
        var line = Text("\(active.activeCount) active")
            .foregroundStyle(SignuColor.textSecondary)
        if active.overdueCount > 0 {
            line = line + Text(" · ").foregroundStyle(SignuColor.textSecondary)
                + Text("\(active.overdueCount) overdue")
                    .foregroundStyle(SignuColor.red)
                    .underline()
        }
        if let delta = active.deltaVsPreviousMonth {
            let sign = delta > 0 ? "+ " : "− "
            line = line + Text(" · ").foregroundStyle(SignuColor.textSecondary)
                + Text("\(sign)\(SignuFormat.brl(abs(delta))) vs \(active.previousMonthAbbrev)")
                    .foregroundStyle(SignuColor.textSecondary)
        }
        return line.font(.signuSubtitleEmphasis)
    }

    private func syncRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.signuSubtitle)
        }
        .foregroundStyle(SignuColor.textSecondary)
    }

    private func comingUpHeader(showCalendar: Bool) -> some View {
        HStack {
            Text("Coming up")
                .font(.signuSection)
                .foregroundStyle(SignuColor.textPrimary)
            Spacer()
            if showCalendar {
                Button("Calendar", action: actions.onCalendar)
                    .font(.signuSubtitleEmphasis)
                    .foregroundStyle(SignuColor.textPrimary)
                    .buttonStyle(.plain)
            }
        }
    }

    // Overdue: standalone tinted row above "Coming up" — never the banner.
    // Multiple overdue runs stack; payment failures are never summarized away.
    private func overdueRow(_ item: HomePayload.OverdueItem) -> some View {
        Button {
            actions.onSelectSubscription(item.subscriptionId)
        } label: {
            SignuRow(
                title: item.serviceName,
                subtitle: Text("Overdue · \(item.daysOverdue) days").foregroundStyle(SignuColor.red),
                trailingTitle: Text(SignuFormat.brl(item.amount, approximate: item.approximate))
            ) {
                DateBadge(date: item.expectedDate, overdue: true)
            }
            .tintedSurface(
                fill: SignuColor.overdueRowFill,
                stroke: SignuColor.overdueRowStroke,
                cornerRadius: SignuMetric.cardRadius
            )
        }
        .buttonStyle(.plain)
    }

    private func comingUpRow(_ item: HomePayload.ComingUpItem) -> some View {
        Button {
            actions.onSelectSubscription(item.subscriptionId)
        } label: {
            SignuRow(
                title: item.serviceName,
                subtitle: Text(daysAwayText(item.daysAway)),
                trailingTitle: Text(SignuFormat.brl(item.amount, approximate: item.approximate))
            ) {
                DateBadge(date: item.date)
            }
        }
        .buttonStyle(.plain)
    }

    private func daysAwayText(_ days: Int) -> String {
        switch days {
        case 0: "today"
        case 1: "in 1 day"
        default: "in \(days) days"
        }
    }

    // 13pt is the largest size at which the locked copy fits one line in
    // Inter beside the badge and "Review →" — the mockup face is narrower.
    private func reviewPill(count: Int) -> some View {
        Button(action: actions.onReview) {
            HStack(spacing: 10) {
                Circle()
                    .fill(SignuColor.green)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text("\(count)")
                            .font(SignuFont.font(13, .semibold, tabular: true))
                            .foregroundStyle(.white)
                    }
                Text("Possible subscriptions detected")
                    .font(SignuFont.font(13, .semibold))
                    .foregroundStyle(SignuColor.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.95)
                Spacer(minLength: 6)
                Text("Review →")
                    .font(SignuFont.font(13, .semibold))
                    .foregroundStyle(SignuColor.green)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .tintedSurface(fill: SignuColor.greenTint, stroke: SignuColor.greenTintStroke, cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }

    private func subscriptionRow(_ item: HomePayload.SubscriptionItem) -> some View {
        Button {
            actions.onSelectSubscription(item.id)
        } label: {
            SignuRow(
                title: item.serviceName,
                subtitle: item.overdueDays.map { Text("Overdue · \($0) days").foregroundStyle(SignuColor.red) }
                    ?? Text(item.subtitle),
                trailingTitle: Text(SignuFormat.brl(item.amount, approximate: item.approximate)),
                trailingSubtitle: Text(SignuFormat.monthDay(item.nextDate))
                    .foregroundStyle(item.overdueDays != nil ? SignuColor.red : SignuColor.textSecondary)
            ) {
                ServiceAvatar(name: item.serviceName)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Dashed-outline empty slot (21g/21h "Coming up").
struct EmptyDashCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.signuSubtitleEmphasis)
                .foregroundStyle(SignuColor.textSecondary)
            Text(subtitle)
                .font(.signuSubtitle)
                .foregroundStyle(SignuColor.textTertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .overlay {
            RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous)
                .strokeBorder(SignuColor.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
        }
    }
}

#Preview("Home · active (21i)") {
    HomeScreen(provider: MockDataProvider())
}

// Bottom-of-scroll spacing must always be reviewed in its real context:
// inside the shell, tab bar overlaid, scrolled to the very end.
#Preview("Home · in shell, scrolled to bottom") {
    RootView(homeScrollAnchor: .bottom)
}

#Preview("Home · watching (21h)") {
    HomeScreen(provider: MockDataProvider(scenario: .freshConnection))
}

#Preview("Home · no bank (21g)") {
    HomeScreen(provider: MockDataProvider(scenario: .noBank))
}

#Preview("Home · no banner, no overdue") {
    struct Host: View {
        @State private var payload: HomePayload?
        var body: some View {
            Group {
                if var payload {
                    HomeView(payload: {
                        payload.banner = nil
                        if case .active(var active) = payload.content {
                            active.overdue = []
                            active.overdueCount = 0
                            payload.content = .active(active)
                        }
                        return payload
                    }())
                } else {
                    Color.clear.task {
                        payload = try? await MockDataProvider().homePayload()
                    }
                }
            }
        }
    }
    return Host()
}
