import Foundation

// Settings payloads. Attribution follows the doctrine: a subscription is
// "via this bank" iff its latest charge (of its latest run) resolves through
// transaction_id to an account under the connection.
//
// Moved verbatim out of MockDataProvider+Settings.swift so the live provider
// shares it. See PayloadSource.swift for why.

extension SignuPayloadSource {

    // MARK: - Settings (12a/12d)

    func makeSettingsPayload() -> SettingsPayload {
        let banks = connectionList.map { connection -> SettingsPayload.BankRow in
            let (chipText, chipTone, subtitle) = bankStatus(connection)
            return SettingsPayload.BankRow(
                id: connection.id, name: bankLabel(connection),
                subtitle: subtitle, chipText: chipText, chipTone: chipTone
            )
        }
        let dismissed = subscriptionList
            .filter(\.ignored)
            .sorted { $0.createdAt > $1.createdAt }
            .map { sub in
                SettingsPayload.DismissedRow(
                    id: sub.id, name: sub.displayName,
                    subtitle: "Not a subscription · \(SignuFormat.monthDay(sub.createdAt))"
                )
            }
        return SettingsPayload(
            displayName: profileValue.displayName,
            email: profileValue.email,
            initial: settingsInitial,
            avatarPath: profileValue.avatarPath,
            displayNameIsFallback: profileValue.displayNameIsFallback,
            providers: profileValue.providers.map(providerLabel),
            // The raw identity, not the label: `providerLabel` renders "email" as
            // "Password" for the chip, and matching on display copy would break
            // the moment that copy changed.
            hasPassword: profileValue.providers.contains("email"),
            banks: banks,
            dismissed: dismissed,
            deleteScopeLine: "Everything, permanently — banks, history, profile"
        )
    }

    /// The monogram beside the identity. Uppercased first letter of the name, or of
    /// the email when the name is standing in — an address that begins with a
    /// non-letter would otherwise render as punctuation in an ink circle.
    private var settingsInitial: String {
        let source = profileValue.displayNameIsFallback
            ? profileValue.email
            : profileValue.displayName
        return String(source.prefix(1)).uppercased()
    }

    private func providerLabel(_ raw: String) -> String {
        switch raw {
        case "google": "Google"
        case "email": "Password"
        default: raw.capitalized
        }
    }

    /// Chip + subtitle by connection health (12a rows).
    private func bankStatus(_ connection: Connection) -> (String, StatusChip.Tone, String) {
        let cardCount = accountList.filter { $0.connectionId == connection.id }.count
        switch connection.status {
        case .needsAction, .expired:
            // A bank that has NEVER synced is not a bank that needs reconnecting
            // (v55). `register-connection` writes `needs_action` on purpose — nothing
            // has been fetched yet, and claiming `active` would be a claim — and the
            // first sync flips it seconds later. In that window this row used to say
            // "Reconnect to resume syncing" about a connection that had just been
            // made successfully and was working, which is the one reading of the
            // state that is actively false.
            //
            // `lastSyncedAt == nil` is what separates the two: no sync has ever
            // completed, so there is nothing to *resume*.
            if connection.lastSyncedAt == nil {
                return ("Setting up", .neutral, "First sync in progress — this takes a moment")
            }
            return ("Needs action", .danger, "Reconnect to resume syncing")
        case .disconnected:
            return ("Disconnected", .neutral, "Reconnect to resume syncing")
        case .active:
            if let expires = connection.consentExpiresAt, daysBetween(today, expires) <= 30 {
                return ("Expiring", .warning, "Consent expires \(SignuFormat.monthDay(expires)) · renew soon")
            }
            let synced = connection.lastSyncedAt.map { "Synced \(SignuFormat.ago($0, now: now))" } ?? "Connected"
            return ("Active", .positive, "\(synced) · \(cardCount) card\(cardCount == 1 ? "" : "s")")
        }
    }

    // MARK: - Connection detail (12b)

    func makeConnectionDetailPayload(connectionId: UUID) -> ConnectionDetailPayload? {
        guard let connection = connectionList.first(where: { $0.id == connectionId }) else { return nil }
        let (chipText, chipTone, _) = bankStatus(connection)
        let cards = accountList.filter { $0.connectionId == connectionId }

        let attributed = attributedSubscriptions(connectionId: connectionId)
        let nonDismissed = attributed.filter { !$0.ignored }

        let cardRows = cards.map { card -> ConnectionDetailPayload.CardRow in
            let count = nonDismissed.filter { subAccount($0)?.id == card.id }.count
            return ConnectionDetailPayload.CardRow(
                id: card.id,
                brandMark: brandMark(card.brand),
                label: "\(brandShort(card.brand)) – \(card.last4)",
                subtitle: count == 0 ? "No subscriptions billed here"
                    : "\(count) subscription\(count == 1 ? "" : "s") billed here"
            )
        }

        let needsReconnect = connection.status != .active
            || (connection.consentExpiresAt.map { daysBetween(today, $0) <= 30 } ?? false)

        return ConnectionDetailPayload(
            id: connection.id,
            institutionName: bankLabel(connection),
            // "via Open Finance" is HARDCODED and is not true of every connection.
            // Connector 200 is Pluggy's credentials-based own-accounts aggregator, which
            // carries no Open Finance consent -- which is also why `consentExpiresText`
            // below renders "—" on the live connection. Documented in v73 and left
            // alone on purpose: `BankLabel.proxyConnectorIds` already holds the fact
            // that would derive this honestly, if it is ever wanted.
            connectedSinceText: "Connected \(SignuFormat.monthYearLong(connection.createdAt)) · via Open Finance",
            statusText: chipText, statusTone: chipTone,
            lastSyncedText: connection.lastSyncedAt.map(SignuFormat.syncStamp) ?? "—",
            // Null is a REAL state, not a gap: no consent exists (connector 200), or a
            // consent exists that never expires (Open Finance's documented default), or
            // it is not known yet. All three render "—", which the reader cannot
            // disambiguate. v73 records the conflation instead of inventing copy for it.
            consentExpiresText: connection.consentExpiresAt.map(SignuFormat.monthDay) ?? "—",
            needsReconnect: needsReconnect,
            reassurance: reassurance(connection),
            cards: cardRows,
            summaryCount: attributed.count,
            summaryTotalText: attributedTotalLine(attributed)
        )
    }

    private func reassurance(_ connection: Connection) -> String {
        let tail = "Reconnecting resumes syncing — nothing was lost."
        if let error = connection.lastSyncError { return "\(error) \(tail)" }
        if let expires = connection.consentExpiresAt, daysBetween(today, expires) <= 30 {
            return "Consent expires \(SignuFormat.monthDay(expires)). Renewing keeps syncing — nothing is lost."
        }
        return "This bank is syncing normally. Signing in again resumes syncing — nothing is lost."
    }

    // MARK: - Attributed subscriptions (13a)

    func makeAttributedSubsPayload(connectionId: UUID) -> AttributedSubsPayload? {
        guard let connection = connectionList.first(where: { $0.id == connectionId }) else { return nil }
        let attributed = attributedSubscriptions(connectionId: connectionId)
        let cards = accountList.filter { $0.connectionId == connectionId }

        let groups = cards.compactMap { card -> AttributedSubsPayload.CardGroup? in
            let subs = attributed.filter { !$0.ignored && subAccount($0)?.id == card.id }
            guard !subs.isEmpty else { return nil }
            return AttributedSubsPayload.CardGroup(
                id: card.id,
                header: "\(brandGroup(card.brand)) ···· \(card.last4) · \(subs.count)",
                rows: subs.map(attributedRow)
            )
        }
        let dismissed = attributed.filter(\.ignored).map { sub in
            AttributedSubsPayload.Row(
                id: sub.id, serviceName: sub.displayName,
                statusLine: "Not a subscription · \(SignuFormat.monthDay(sub.createdAt))",
                statusTone: .neutral, amountText: nil, unit: nil
            )
        }

        return AttributedSubsPayload(
            institutionName: bankLabel(connection),
            institutionInitial: String(bankLabel(connection).prefix(1)).uppercased(),
            headerCount: attributed.count,
            headerLine: "\(attributed.count) subscription\(attributed.count == 1 ? "" : "s") · \(attributedTotalLine(attributed))",
            cardGroups: groups,
            dismissed: dismissed
        )
    }

    private func attributedRow(_ sub: Subscription) -> AttributedSubsPayload.Row {
        guard let run = latestRunFor(sub.id), let charge = latestChargeFor(run.id) else {
            return AttributedSubsPayload.Row(id: sub.id, serviceName: sub.displayName,
                                             statusLine: "", statusTone: .neutral, amountText: nil, unit: nil)
        }
        let approx = run.detectedBy.isApproximate
        let unit = run.billingInterval == .monthly ? "/mo" : "/yr"
        let annualTag = run.billingInterval == .annual ? " · annual" : ""
        let line: String
        var tone: StatusChip.Tone = .neutral
        switch run.status {
        case .overdue:
            line = "Overdue · expected \(SignuFormat.monthDay(run.nextExpectedDate ?? charge.date))"
            tone = .danger
        case .active, .possible:
            line = "Renews \(SignuFormat.monthDay(run.nextExpectedDate ?? charge.date))\(annualTag)"
        case .ended:
            line = "Ended · paid through \(SignuFormat.monthDay(run.endDate ?? charge.date))"
        case .cancelled:
            line = "Cancelled · paid through \(SignuFormat.monthDay(run.endDate ?? charge.date))"
        }
        return AttributedSubsPayload.Row(
            id: sub.id, serviceName: sub.displayName, statusLine: line, statusTone: tone,
            amountText: SignuFormat.brl(charge.amount, approximate: approx), unit: unit
        )
    }

    // MARK: - Delete-account

    func makeDeleteAccountScope() -> DeleteAccountScope {
        let since = chargeList.map(\.date).min()
        return DeleteAccountScope(
            bankCount: connectionList.count,
            subscriptionCount: subscriptionList.count,   // includes ignored + suggestions
            sinceText: since.map(SignuFormat.monthYearShort) ?? "—"
        )
    }

    // MARK: - Attribution helpers

    /// All subscriptions (incl. dismissed) whose latest charge resolves to
    /// this connection.
    private func attributedSubscriptions(connectionId: UUID) -> [Subscription] {
        subscriptionList.filter { subAccount($0)?.connectionId == connectionId }
    }

    private func attributedTotalLine(_ subs: [Subscription]) -> String {
        let runIds = Set(runList.filter { run in subs.contains { $0.id == run.subscriptionId } }.map(\.id))
        let total = chargeList.filter { runIds.contains($0.runId) }.reduce(Decimal.zero) { $0 + $1.amount }
        let since = subs
            .compactMap { sub in runList.filter { $0.subscriptionId == sub.id }.map(\.startDate).min() }
            .min()
        return "\(SignuFormat.brl(total)) since \(since.map(SignuFormat.monthYearShort) ?? "—")"
    }

    private func subAccount(_ sub: Subscription) -> BankAccount? {
        guard let run = latestRunFor(sub.id),
              let charge = latestChargeFor(run.id),
              let tx = charge.transactionId,
              let accountId = transactionAccountMap[tx] else { return nil }
        return accountList.first { $0.id == accountId }
    }

    private func latestRunFor(_ subscriptionId: UUID) -> SubscriptionRun? {
        runList.filter { $0.subscriptionId == subscriptionId }.max { $0.startDate < $1.startDate }
    }

    private func latestChargeFor(_ runId: UUID) -> Charge? {
        chargeList.filter { $0.runId == runId }.max { $0.date < $1.date }
    }

    private func daysBetween(_ from: Date, _ to: Date) -> Int {
        Self.calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    // MARK: - Brand display

    private func brandMark(_ brand: String?) -> String {
        switch brand?.lowercased() {
        case "visa": "VISA"
        case "mastercard": "MC"
        case "elo": "ELO"
        default: "•••"
        }
    }

    private func brandShort(_ brand: String?) -> String {
        switch brand?.lowercased() {
        case "mastercard": "Master"
        case .some(let value): value.prefix(1).uppercased() + value.dropFirst()
        default: "Account"
        }
    }

    private func brandGroup(_ brand: String?) -> String {
        switch brand?.lowercased() {
        case "visa": "VISA"
        case "mastercard": "MASTER"
        case "elo": "ELO"
        default: "CARD"
        }
    }
}
