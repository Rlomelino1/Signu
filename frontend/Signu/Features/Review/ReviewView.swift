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
    /// SUBSCRIPTION id → subscription.ignored = true. Was the run id, which named
    /// the row the button sits on rather than the row the write targets — dismissing
    /// is a statement about the subscription ("not a subscription"), not about one
    /// run of it, and a suggestion carries both ids anyway.
    var onDismiss: (UUID) -> Void = { _ in }
    /// SUBSCRIPTION id → `remind_before_days = 2`, the same write the detail
    /// screen's toggle makes. Only fires on "Remind me": declining writes
    /// nothing, because a decline is not a state a subscription should carry.
    var onRemind: (UUID) -> Void = { _ in }
}

/// Review screen (9a — mockup 21j): full charge evidence per possible run,
/// Track it / Not a subscription. 9b informs, 9a decides.
struct ReviewView: View {
    let payload: ReviewPayload
    var actions = ReviewActions()

    /// Dismissed rows animate out. Confirmed ones do NOT — they are replaced in
    /// place by a confirmation card (22b), so the queue above them is untouched
    /// and the user reads the reminder offer next to the thing they just
    /// confirmed. The rows are gone on the next visit either way: review lists
    /// `possible` runs, and a confirmed one has moved to the Subs tab while a
    /// dismissed one has moved to Settings.
    @State private var resolved: Set<UUID> = []
    /// Confirmed this session → the interval it was confirmed with.
    @State private var confirmed: [UUID: BillingInterval] = [:]
    /// The one confirmation carrying the reminder offer, and whether it has been
    /// answered. Answering collapses the card rather than removing it.
    @State private var offering: UUID?
    @State private var intervalPrompt: ReviewPayload.Suggestion?
    /// Screenshot harness: auto-open the R4 interval sheet on appear.
    var autoPresentIntervalForR4 = false

    private var remaining: [ReviewPayload.Suggestion] {
        payload.suggestions.filter { !resolved.contains($0.id) }
    }

    /// Offered once, on the first confirmation by a user who has never used
    /// reminders. `remindersNeverUsed` covers the durable half (a "yes" leaves a
    /// `remind_before_days` behind); `ReminderOffer.answered` covers the "no",
    /// which deliberately writes nothing to the database.
    private var offersReminder: Bool {
        payload.remindersNeverUsed && !ReminderOffer.answered
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if remaining.isEmpty {
                    allCaughtUp
                } else {
                    ForEach(remaining) { suggestion in
                        if let interval = confirmed[suggestion.id] {
                            confirmationCard(suggestion, interval: interval)
                        } else {
                            card(suggestion)
                        }
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

    // Chevron on the left, title on the same row starting just right of it,
    // subtitle directly under the title (21j).
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ChromeButton(systemName: "chevron.left", action: actions.onBack)
            VStack(alignment: .leading, spacing: 3) {
                Text("Possible subscriptions")
                    .font(.signuTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Found in your transactions — you decide.")
                    .font(.signuSubtitle)
                    .foregroundStyle(SignuColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.top, 4)
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

    // MARK: - Confirmation card (22b)

    /// What a confirmed row becomes, in place. Collapsed to the header alone once
    /// the offer is answered — or immediately, when there is no offer to make.
    private func confirmationCard(
        _ suggestion: ReviewPayload.Suggestion,
        interval: BillingInterval
    ) -> some View {
        SignuCard(background: SignuColor.sunken.opacity(0.7)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ServiceAvatar(name: suggestion.serviceName, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(suggestion.serviceName) is now tracked")
                            .font(.signuRowTitle)
                            .foregroundStyle(SignuColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        // Bare date, tilde amount — the tilde rule is amounts-only
                        // (locked 2026-07-15), and a predicted date carries the
                        // same ±3-day window whatever rule found it.
                        Text("\(interval == .annual ? "Annual" : "Monthly") · renews \(SignuFormat.monthDay(suggestion.renewsDate)) · \(SignuFormat.brl(suggestion.renewsAmount, approximate: true))")
                            .font(SignuFont.font(13, .semibold))
                            .foregroundStyle(SignuColor.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(SignuColor.green)
                }

                if offering == suggestion.id {
                    reminderOffer(suggestion)
                }
            }
            .padding(16)
        }
    }

    /// The offer, nested inside the confirmation so it reads as being about the
    /// thing just confirmed rather than about the app in general.
    private func reminderOffer(_ suggestion: ReviewPayload.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Want a heads-up before it renews?")
                .font(SignuFont.font(16, .semibold))
                .foregroundStyle(SignuColor.textPrimary)
            // Every claim here is one the pipeline actually keeps: email only,
            // two days, to the address the account was created with. Push exists
            // in the schema and is deliberately unbuilt, so it is not mentioned.
            Text("One email, 2 days before the expected charge — sent to the address you signed in with.")
                .font(.signuBody)
                .foregroundStyle(SignuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button { answerOffer(suggestion, remind: true) } label: {
                    Label("Remind me", systemImage: "bell").lineLimit(1)
                }
                .buttonStyle(.signuSuccess)
                Button("No thanks") { answerOffer(suggestion, remind: false) }
                    .buttonStyle(.signuSecondary)
            }

            Text("We won't ask again — reminders live on each subscription's detail screen.")
                .font(SignuFont.font(13))
                .foregroundStyle(SignuColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        // Replaced in place rather than animated away: the confirmation is the
        // acknowledgement, and on a first confirmation it carries the reminder
        // offer. Only the first one offers — a second confirmation in the same
        // session shows the compact card alone.
        withAnimation(.easeOut(duration: 0.25)) {
            confirmed[suggestion.id] = interval ?? suggestion.billingInterval
            if offering == nil && offersReminder { offering = suggestion.id }
        }
    }

    private func answerOffer(_ suggestion: ReviewPayload.Suggestion, remind: Bool) {
        // Either answer ends the offer for good. "Yes" also writes the reminder,
        // which is what makes the decision durable without a column of its own.
        ReminderOffer.answered = true
        if remind { actions.onRemind(suggestion.subscriptionId) }
        withAnimation(.easeOut(duration: 0.2)) { offering = nil }
    }

    private func dismiss(_ suggestion: ReviewPayload.Suggestion) {
        actions.onDismiss(suggestion.subscriptionId)
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
            // The R4 sheet's two choices are the only way to confirm a
            // single-charge suggestion, so a dead middle here blocks the flow.
            .contentShape(Rectangle())
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
