import SwiftUI

struct ConnectionDetailScreen: View {
    let provider: SignuDataProviding
    let connectionId: UUID
    var onBack: () -> Void = {}
    /// Reported after a successful re-authentication, so Settings stops
    /// rendering the state this link was in before it.
    var onReconnected: () -> Void = {}

    @State private var payload: ConnectionDetailPayload?
    @State private var showRemove = false
    @State private var attributedId: UUID?
    /// The removal's failure has to render here rather than in the shell: this
    /// screen is a full-screen cover, and an alert attached below it never
    /// appears.
    @State private var removeError: String?
    /// 12b presents the connect flow itself. It cannot delegate that upwards: a
    /// full-screen cover will not present another cover, so a request to the
    /// shell arrives and does nothing.
    @State private var connectTarget: ConnectTarget?

    var body: some View {
        Group {
            if let payload {
                ConnectionDetailView(
                    payload: payload,
                    onBack: onBack,
                    onOpenAttributed: { attributedId = connectionId },
                    onRemove: { showRemove = true },
                    onReconnect: { connectTarget = ConnectTarget(connectionId: connectionId) }
                )
            } else {
                Color.clear
            }
        }
        .task { payload = try? await provider.connectionDetailPayload(connectionId: connectionId) }
        .sheet(isPresented: $showRemove) {
            if let payload {
                // The sheet's radio choice travels with the tap. It has to: the
                // Edge Function deletes attributed subscriptions BEFORE the
                // connection, because attribution runs through
                // `charge.transaction_id` and the connection's own deletion NULLs
                // it. Asked afterwards, the question has no answer left.
                RemoveBankSheet(institutionName: payload.institutionName, count: payload.summaryCount) { keepHistory in
                    Task {
                        do {
                            try await provider.removeConnection(
                                connectionId: connectionId,
                                deleteHistory: !keepHistory
                            )
                            showRemove = false
                            onBack()   // link removed → back to Settings
                        } catch {
                            showRemove = false
                            removeError = error.localizedDescription
                        }
                    }
                }
                .presentationDetents([.height(560)])
                .presentationDragIndicator(.visible)
            }
        }
        .alert(
            "That didn't go through",
            isPresented: Binding(get: { removeError != nil }, set: { if !$0 { removeError = nil } })
        ) {
            Button("OK", role: .cancel) { removeError = nil }
        } message: {
            Text(removeError ?? "")
        }
        .fullScreenCover(item: $attributedId) { id in
            AttributedSubsScreen(provider: provider, connectionId: id, onBack: { attributedId = nil })
        }
        .connectBankCover(provider: provider, target: $connectTarget) {
            // Re-read before reporting: the item's status and consent date have
            // just changed, and this screen renders both.
            Task {
                payload = try? await provider.connectionDetailPayload(connectionId: connectionId)
                onReconnected()
            }
        }
    }
}

/// Connection detail (12b — mockup 21v).
struct ConnectionDetailView: View {
    let payload: ConnectionDetailPayload
    var onBack: () -> Void = {}
    var onOpenAttributed: () -> Void = {}
    var onRemove: () -> Void = {}
    var onReconnect: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { ChromeButton(systemName: "chevron.left", action: onBack); Spacer() }
                        .padding(.top, 4)
                    hero
                    cardsSection
                    if payload.summaryCount > 0 { summaryRow }
                }
                .padding(.horizontal, SignuMetric.screenPadding)
                .padding(.bottom, 120)
            }
            removeBar
        }
        .background(SignuColor.paper)
    }

    private var hero: some View {
        InkHeroCard {
            HStack(alignment: .center, spacing: 13) {
                ServiceAvatar(name: payload.institutionName, size: 46, kind: .institution)
                VStack(alignment: .leading, spacing: 2) {
                    Text(payload.institutionName)
                        .font(.signuHeadline)
                        .foregroundStyle(SignuColor.onInk)
                    Text(payload.connectedSinceText)
                        .font(SignuFont.font(13))
                        .foregroundStyle(SignuColor.onInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                StatusChip(text: payload.statusText, tone: payload.statusTone, onInk: true).fixedSize()
            }
            .padding(.bottom, 16)

            HStack(spacing: 12) {
                HeroStatTile(label: "Last synced", value: payload.lastSyncedText)
                HeroStatTile(label: "Consent expires", value: payload.consentExpiresText)
            }

            if payload.needsReconnect {
                Button("Reconnect \(payload.institutionName)", action: onReconnect)
                    .buttonStyle(.signuOnInk)
                    .padding(.top, 14)
            }

            Text(payload.reassurance)
                .font(SignuFont.font(14))
                .foregroundStyle(SignuColor.onInkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Cards on this link")
            SignuListCard(data: payload.cards) { card in
                HStack(spacing: 14) {
                    CardBadge(mark: card.brandMark)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.label.signuNonBreaking)
                            .font(.signuRowTitle)
                            .foregroundStyle(SignuColor.textPrimary)
                        Text(card.subtitle)
                            .font(SignuFont.font(14))
                            .foregroundStyle(SignuColor.textSecondary)
                    }
                    Spacer()
                }
                .padding(SignuMetric.rowPaddingH)
            }
        }
    }

    private var summaryRow: some View {
        Button(action: onOpenAttributed) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(payload.summaryCount) subscriptions found via this bank")
                        .font(.signuSubtitleEmphasis)
                        .foregroundStyle(SignuColor.textPrimary)
                    Text(payload.summaryTotalText)
                        .font(SignuFont.font(14))
                        .foregroundStyle(SignuColor.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SignuColor.textSecondary)
            }
            .padding(16)
            .background(SignuColor.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous))
            // As everywhere else: the fill is painted, not hit-tested.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var removeBar: some View {
        Button("Remove this bank link", action: onRemove)
            .buttonStyle(.signuDestructiveOutline)
            .padding(.horizontal, SignuMetric.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(alignment: .top) {
                SignuColor.paper.ignoresSafeArea()
                    .overlay(alignment: .top) { Rectangle().fill(SignuColor.hairline).frame(height: 1) }
            }
    }
}

/// Small brand badge for a card row ("VISA" / "MC" / "ELO").
struct CardBadge: View {
    let mark: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(background)
            .frame(width: 44, height: 32)
            .overlay {
                Text(mark)
                    .font(SignuFont.font(12, .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
    }

    private var background: Color {
        switch mark {
        case "VISA": SignuColor.blue
        case "ELO": SignuColor.gold
        default: SignuColor.ink
        }
    }
}

/// Remove-bank sheet (12c — mockup 21w). History choice captured up front.
struct RemoveBankSheet: View {
    let institutionName: String
    let count: Int
    /// Carries the history choice, because the caller cannot ask for it later —
    /// see the sequencing rule at the call site.
    var onRemove: (Bool) -> Void = { _ in }

    @State private var keepHistory = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Remove \(institutionName)?")
                    .font(.signuTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                Text("Syncing stops and this bank's transactions are deleted from the app.")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
            }

            OverlineText("What about the \(count) subscriptions we found here?")

            VStack(spacing: 12) {
                choice(
                    selected: keepHistory, title: "Keep their history",
                    detail: "They stay in your list with their charge history — they just stop updating from this bank."
                ) { keepHistory = true }
                choice(
                    selected: !keepHistory, title: "Delete them too",
                    detail: "Erases those \(count) subscriptions (including dismissed ones) and their charge history."
                ) { keepHistory = false }
            }

            Button(keepHistory ? "Remove link, keep history" : "Remove link and history") {
                onRemove(keepHistory)
            }
                .buttonStyle(.signuDestructiveFilled)
                .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SignuColor.paper)
    }

    private func choice(selected: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? SignuColor.ink : SignuColor.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.signuRowTitle)
                        .foregroundStyle(SignuColor.textPrimary)
                    Text(detail)
                        .font(SignuFont.font(14))
                        .foregroundStyle(SignuColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? SignuColor.sunken.opacity(0.6) : SignuColor.surface,
                        in: RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous)
                    .strokeBorder(selected ? SignuColor.ink : SignuColor.hairline, lineWidth: selected ? 1.5 : 1)
            }
            // 12c's history choice decides whether data is deleted. A radio the
            // user believes they selected, that did not select, is the worst
            // possible place for this bug.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Connection detail (12b)") {
    let provider = MockDataProvider()
    let itau = provider.connectionList.first { $0.institutionName == "Itaú" }!
    return ConnectionDetailScreen(provider: provider, connectionId: itau.id)
}

#Preview("Remove bank sheet (12c)") {
    SignuColor.paper.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            RemoveBankSheet(institutionName: "Itaú", count: 6)
                .presentationDetents([.height(560)])
        }
}
