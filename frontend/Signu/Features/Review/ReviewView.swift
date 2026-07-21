import SwiftUI

/// Loads the review payload from the provider and renders 9a.
struct ReviewScreen: View {
    let provider: SignuDataProviding
    var actions = ReviewActions()
    var autoPresentIntervalForR4 = false

    @State private var payload: ReviewPayload?

    var body: some View {
        Group {
            if let payload {
                ReviewView(payload: payload, actions: actions, autoPresentIntervalForR4: autoPresentIntervalForR4)
            } else {
                Color.clear
            }
        }
        .task {
            payload = try? await provider.reviewPayload()
        }
    }
}

struct ReviewActions {
    var onBack: () -> Void = {}
    /// run id, chosen interval (nil = R3, already measured).
    var onTrack: (UUID, BillingInterval?) -> Void = { _, _ in }
    /// run id → subscription.ignored = true.
    var onDismiss: (UUID) -> Void = { _ in }
}

/// Review screen (9a — mockup 21j): full charge evidence per possible run,
/// Track it / Not a subscription. 9b informs, 9a decides.
struct ReviewView: View {
    let payload: ReviewPayload
    var actions = ReviewActions()

    // UI-only resolution for the mock: confirmed/dismissed rows animate out.
    @State private var resolved: Set<UUID> = []
    @State private var intervalPrompt: ReviewPayload.Suggestion?
    /// Screenshot harness: auto-open the R4 interval sheet on appear.
    var autoPresentIntervalForR4 = false

    private var remaining: [ReviewPayload.Suggestion] {
        payload.suggestions.filter { !resolved.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if remaining.isEmpty {
                    allCaughtUp
                } else {
                    ForEach(remaining) { suggestion in
                        card(suggestion)
                    }
                    Text("Dismissed suggestions can be restored in Settings.")
                        .font(.signuSubtitle)
                        .foregroundStyle(SignuColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, SignuMetric.screenPadding)
            .padding(.bottom, 40)
        }
        .background(SignuColor.paper)
        .sheet(item: $intervalPrompt) { suggestion in
            IntervalPromptSheet(serviceName: suggestion.serviceName) { interval in
                track(suggestion, interval: interval)
                intervalPrompt = nil
            }
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            if autoPresentIntervalForR4 {
                intervalPrompt = payload.suggestions.first { $0.asksIntervalOnTrack }
            }
        }
    }

    // MARK: - Header

    // Chevron on its own row, title full-width below — same pushed-screen
    // header pattern as the detail screen (21k).
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            ChromeButton(systemName: "chevron.left", action: actions.onBack)
            VStack(alignment: .leading, spacing: 3) {
                Text("Possible subscriptions")
                    .font(.signuTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Found in your transactions — you decide.")
                    .font(.signuSubtitle)
                    .foregroundStyle(SignuColor.textSecondary)
            }
        }
        .padding(.top, 4)
    }

    private var allCaughtUp: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(SignuColor.green)
            Text("You're all caught up")
                .font(.signuSection)
                .foregroundStyle(SignuColor.textPrimary)
            Text("New possible subscriptions will show up here as they're found.")
                .font(.signuBody)
                .foregroundStyle(SignuColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 20)
    }

    // MARK: - Suggestion card

    private func card(_ suggestion: ReviewPayload.Suggestion) -> some View {
        SignuCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ServiceAvatar(name: suggestion.serviceName, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.serviceName)
                            .font(.signuRowTitle)
                            .foregroundStyle(SignuColor.textPrimary)
                        // One line, per 21j — 13pt scales to fit the longest
                        // R3 evidence copy in Inter.
                        Text(suggestion.evidence)
                            .font(SignuFont.font(13, .semibold))
                            .foregroundStyle(SignuColor.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                evidenceList(suggestion.charges)

                // Prediction: bare date, tilde amount (tilde rule — amounts only).
                Text("If confirmed: renews \(SignuFormat.monthDay(suggestion.renewsDate)) · \(SignuFormat.brl(suggestion.renewsAmount, approximate: true))")
                    .font(.signuSubtitle)
                    .foregroundStyle(SignuColor.textSecondary)

                HStack(spacing: 12) {
                    Button {
                        trackTapped(suggestion)
                    } label: {
                        Text("Track it").lineLimit(1)
                    }
                    .buttonStyle(SignuButtonStyle(kind: .success, compact: true))
                    Button {
                        dismiss(suggestion)
                    } label: {
                        Text("Not a subscription").lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .buttonStyle(SignuButtonStyle(kind: .secondary, compact: true))
                }
                .padding(.top, 2)
            }
            .padding(16)
        }
    }

    private func evidenceList(_ charges: [ReviewPayload.ChargeLine]) -> some View {
        VStack(spacing: 0) {
            ForEach(charges) { charge in
                HStack(spacing: 10) {
                    Circle()
                        .fill(SignuColor.green.opacity(0.55))
                        .frame(width: 8, height: 8)
                    Text("\(charge.dateText) · \(charge.cardLabel)".signuNonBreaking)
                        .font(.signuSubtitle)
                        .foregroundStyle(SignuColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(SignuFormat.brl(charge.amount))
                        .font(.signuSubtitleEmphasis)
                        .foregroundStyle(SignuColor.textPrimary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 2)
        .background(SignuColor.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous))
    }

    // MARK: - Actions

    private func trackTapped(_ suggestion: ReviewPayload.Suggestion) {
        if suggestion.asksIntervalOnTrack {
            intervalPrompt = suggestion       // R4 → ask monthly/annual
        } else {
            track(suggestion, interval: nil)  // R3 → cadence already measured
        }
    }

    private func track(_ suggestion: ReviewPayload.Suggestion, interval: BillingInterval?) {
        actions.onTrack(suggestion.id, interval)
        withAnimation(.easeOut(duration: 0.25)) { _ = resolved.insert(suggestion.id) }
    }

    private func dismiss(_ suggestion: ReviewPayload.Suggestion) {
        actions.onDismiss(suggestion.id)
        withAnimation(.easeOut(duration: 0.25)) { _ = resolved.insert(suggestion.id) }
    }
}

/// R4 confirmation sheet: the single charge can't reveal a cadence, so we
/// ask. The user's answer is the authoritative billing_interval write.
/// (No mockup for this sheet — designed to the system; attaches to exactly
/// one button in one place, per the contract.)
struct IntervalPromptSheet: View {
    let serviceName: String
    var onChoose: (BillingInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How often does \(serviceName) bill?")
                    .font(.signuSection)
                    .foregroundStyle(SignuColor.textPrimary)
                Text("We spotted one charge, so we can't tell the cycle yet. Pick one to start tracking — you can change it later.")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
            }

            VStack(spacing: 12) {
                choice(title: "Monthly", subtitle: "Bills every month", interval: .monthly)
                choice(title: "Annual", subtitle: "Bills once a year", interval: .annual)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SignuColor.paper)
    }

    private func choice(title: String, subtitle: String, interval: BillingInterval) -> some View {
        Button {
            onChoose(interval)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.signuRowTitle)
                        .foregroundStyle(SignuColor.textPrimary)
                    Text(subtitle)
                        .font(.signuSubtitle)
                        .foregroundStyle(SignuColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SignuColor.textTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous)
                    .strokeBorder(SignuColor.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Review (9a · 21j)") {
    ReviewScreen(provider: MockDataProvider())
}

#Preview("Interval prompt (R4)") {
    SignuColor.paper
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            IntervalPromptSheet(serviceName: "Meli+") { _ in }
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
}
