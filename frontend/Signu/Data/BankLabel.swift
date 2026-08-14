import Foundation

/// What to call a bank connection on screen.
///
/// `connection.institution_name` is sync-owned and holds Pluggy's **connector**
/// name, which is the honest raw value and is usually the brand the user knows —
/// "Nubank", "Itaú". For one connector it is not: **connector 200 is `MeuPluggy`**,
/// the own-accounts proxy behind `meu.pluggy.ai`. Its payload names no bank at all
/// (`institutionUrl` is `https://meu.pluggy.ai/`, `imageUrl` is Pluggy's *sandbox*
/// icon), so a connection made through it renders as "MeuPluggy" — accurate about
/// the connector, useless to the person who linked a Nubank account.
///
/// The bank is still in the data, one level down: the checking account arrived as
/// "Nu Pagamentos S.A. - Instituição de Pagamento (Conta Pré-paga)", with
/// `bankData.transferNumber` `260/0001/…` — 260 being Nubank's COMPE code.
///
/// **The derivation is at render time and the raw value is never overwritten.**
/// Storing a derived name in `institution_name` would put an interpretation in a
/// sync-owned column, which is the boundary v26 drew when it kept both amounts
/// rather than reconstructing one from the other. A label is a display concern.
///
/// Not attempted: mapping the COMPE code to a brand ("260" → "Nubank"). It would
/// read better, but it needs seeded reference data for every Brazilian bank and it
/// would still miss credit cards, which carry no `bankData` at all.
enum BankLabel {

    /// Connectors that proxy other institutions rather than being one.
    ///
    /// A set, and matched on the connector **id** rather than its name, because
    /// the id is Pluggy's stable key while the display name is theirs to reword.
    /// Only membership in this set diverts to the account-derived label — for a
    /// real connector the connector name is the better answer and is returned
    /// untouched.
    static let proxyConnectorIds: Set<String> = ["200"]

    /// The institution named by one account's official name, or nil if that name
    /// does not carry one.
    ///
    /// Two trims, each removing something that describes the ACCOUNT rather than
    /// the institution that holds it:
    ///
    ///   "Nu Pagamentos S.A. - Instituição de Pagamento (Conta Pré-paga)"
    ///     → drop the trailing parenthetical  → "Nu Pagamentos S.A. - Instituição de Pagamento"
    ///     → keep what precedes " - "         → "Nu Pagamentos S.A."
    ///
    /// The " - " rule can shorten a bank whose legal name genuinely contains a
    /// spaced hyphen. That is accepted: what precedes the separator is still the
    /// institution, so the label stays true, only less complete.
    ///
    /// **The order of the trims is load-bearing.** Trailing whitespace goes first,
    /// so the parenthetical check below can see the `")"`. Leading whitespace is
    /// deliberately kept until after the `" - "` split: trimming it first turns a
    /// name that BEGINS with the separator into `"- Conta Corrente"`, where the
    /// separator no longer matches and an account descriptor is returned as though
    /// it were a bank. A test caught exactly that.
    static func institution(from accountName: String) -> String? {
        var name = accountName.replacingOccurrences(
            of: "[ \t]+$", with: "", options: .regularExpression
        )

        if name.hasSuffix(")"), let open = name.lastIndex(of: "(") {
            name = String(name[name.startIndex..<open])
        }
        if let separator = name.range(of: " - ") {
            name = String(name[name.startIndex..<separator.lowerBound])
        }
        name = name.trimmingCharacters(in: .whitespaces)

        // A floor, not a validation: "NA", "-" and an empty remainder are worse
        // than saying "MeuPluggy", which is at least a real connector.
        return name.count >= 3 ? name : nil
    }

    /// - Parameter proxiedAccountNames: official names of the connection's
    ///   accounts, **cards excluded and best candidate first** — see
    ///   `SignuPayloadSource.bankLabel`. Ignored entirely for a real connector.
    static func resolve(
        institutionId: String,
        institutionName: String,
        proxiedAccountNames: [String]
    ) -> String {
        guard proxyConnectorIds.contains(institutionId) else { return institutionName }
        for candidate in proxiedAccountNames {
            if let derived = institution(from: candidate) { return derived }
        }
        return institutionName
    }
}

extension SignuPayloadSource {

    /// The connection's name for display. Every screen that labels a bank goes
    /// through here rather than reading `institutionName` directly, so the six
    /// sites cannot drift apart.
    func bankLabel(_ connection: Connection) -> String {
        BankLabel.resolve(
            institutionId: connection.institutionId,
            institutionName: connection.institutionName,
            // Cards are excluded rather than ranked last: a card's official name
            // is its product tier — this ledger's is literally "platinum" — and
            // `bankData` is null on cards, so there is no issuer in there to find.
            // A proxy connection holding only cards therefore keeps the connector
            // name, which is honest about what we know.
            //
            // Sorted so the label does not depend on the order rows came back in:
            // one connection is one bank in practice (a second bank arrives as a
            // second connection), so which of several accounts wins does not
            // change the answer — but it must not change between two reads.
            proxiedAccountNames: accountList
                .filter { $0.connectionId == connection.id && $0.type != .creditCard }
                .map(\.officialName)
                .sorted()
        )
    }
}
