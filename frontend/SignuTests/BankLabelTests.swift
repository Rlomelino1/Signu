import Testing
import Foundation
@testable import Signu

// #1 from the first production run: the bank read "MeuPluggy", not "Nubank".
// Connector 200 is Pluggy's own-accounts proxy, so `institution_name` names the
// proxy rather than the bank — and the bank is one level down, in the account's
// official name. These pin the derivation because it is the kind of rule that
// looks obviously right and silently mislabels a real connector: the trims are
// only correct for a proxy, so "leave a real connector alone" is as much of a
// requirement as "derive for a proxy" and is tested first.

@Suite("Bank label derivation (v43)")
struct BankLabelTests {

    // MARK: - The connector name wins when the connector is a real bank

    @Test("A real connector keeps its name, accounts notwithstanding")
    func realConnectorIsUntouched() {
        let label = BankLabel.resolve(
            institutionId: "212",
            institutionName: "Nubank",
            proxiedAccountNames: ["Nu Pagamentos S.A. - Instituição de Pagamento (Conta Pré-paga)"]
        )
        // Deriving here would REPLACE the brand with a legal name — worse, and
        // the reason membership of `proxyConnectorIds` gates the whole rule.
        #expect(label == "Nubank")
    }

    // MARK: - The proxy defers to the account

    @Test("The MeuPluggy proxy is labelled from the account, trims and all")
    func proxyDerivesFromAccount() {
        let label = BankLabel.resolve(
            institutionId: "200",
            institutionName: "MeuPluggy",
            proxiedAccountNames: ["Nu Pagamentos S.A. - Instituição de Pagamento (Conta Pré-paga)"]
        )
        #expect(label == "Nu Pagamentos S.A.")
    }

    @Test("A hyphenated account label keeps what precedes the separator")
    func separatorTrim() {
        #expect(BankLabel.institution(from: "C6 Bank - Conta Corrente") == "C6 Bank")
    }

    @Test("A parenthetical alone is enough to trim")
    func parentheticalTrim() {
        #expect(BankLabel.institution(from: "Banco Inter S.A. (Conta Digital)") == "Banco Inter S.A.")
    }

    @Test("A name carrying neither marker is returned as it arrived")
    func noMarkers() {
        #expect(BankLabel.institution(from: "Itaú Unibanco S.A.") == "Itaú Unibanco S.A.")
    }

    // MARK: - Falling back rather than inventing

    @Test("Nothing left after trimming is not a bank name")
    func trimmedToNothing() {
        #expect(BankLabel.institution(from: "NA") == nil)
        #expect(BankLabel.institution(from: " - Conta Corrente") == nil)
        #expect(BankLabel.institution(from: "(Conta Pré-paga)") == nil)
    }

    @Test("A proxy with no usable account name keeps the connector name")
    func proxyFallsBackToConnector() {
        let label = BankLabel.resolve(
            institutionId: "200",
            institutionName: "MeuPluggy",
            proxiedAccountNames: ["NA"]
        )
        #expect(label == "MeuPluggy")
    }

    @Test("A proxy with no accounts at all keeps the connector name")
    func proxyWithNoAccounts() {
        let label = BankLabel.resolve(
            institutionId: "200",
            institutionName: "MeuPluggy",
            proxiedAccountNames: []
        )
        #expect(label == "MeuPluggy")
    }

    // MARK: - What the payload layer feeds it

    /// The smallest thing satisfying `SignuPayloadSource`, so `bankLabel` runs for
    /// real rather than against a reimplementation of its filter.
    private struct StubSource: SignuPayloadSource {
        var today = Date(timeIntervalSince1970: 1_780_000_000)
        var now = Date(timeIntervalSince1970: 1_780_000_000)
        var profileValue: Profile!
        var connectionList: [Connection] = []
        var accountList: [BankAccount] = []
        var subscriptionList: [Subscription] = []
        var runList: [SubscriptionRun] = []
        var chargeList: [Charge] = []
        var transactionAccountMap: [UUID: UUID] = [:]
    }

    private static func connection(institutionId: String, name: String) -> Connection {
        Connection(
            id: UUID(), institutionId: institutionId, institutionName: name,
            status: .active, consentExpiresAt: nil, lastSyncedAt: nil,
            lastSyncError: nil, createdAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
    }

    private static func account(
        _ connectionId: UUID, type: AccountType, name: String
    ) -> BankAccount {
        BankAccount(
            id: UUID(), connectionId: connectionId, type: type, brand: nil,
            last4: "0000", officialName: name, nickname: nil, status: .active
        )
    }

    @Test("Cards are excluded: a card's official name is a product tier")
    @MainActor
    func cardsAreNotAskedWhoTheBankIs() {
        let connection = Self.connection(institutionId: "200", name: "MeuPluggy")
        let source = StubSource(
            connectionList: [connection],
            accountList: [
                // This ledger's real card name. Ranking it last would still let it
                // win a connection that holds nothing else, which is why the
                // filter drops cards outright.
                Self.account(connection.id, type: .creditCard, name: "platinum"),
                Self.account(
                    connection.id, type: .checking,
                    name: "Nu Pagamentos S.A. - Instituição de Pagamento (Conta Pré-paga)"
                ),
            ]
        )
        #expect(source.bankLabel(connection) == "Nu Pagamentos S.A.")
    }

    @Test("The second bank behind the same proxy gets its own name")
    @MainActor
    func aggregatorHoldingASecondBank() {
        // Production, verbatim, after the first connection the app ever created
        // (2026-08-17): a second MeuPluggy item holding C6's accounts. The connector
        // says "MeuPluggy" for both banks, so the label can only come from here — and
        // the card is excluded, which matters because 'C6 STANDARD' would otherwise
        // win alphabetically.
        let connection = Self.connection(institutionId: "200", name: "MeuPluggy")
        let source = StubSource(
            connectionList: [connection],
            accountList: [
                Self.account(connection.id, type: .creditCard, name: "C6 STANDARD"),
                Self.account(connection.id, type: .checking, name: "C6 BANK"),
            ]
        )
        #expect(source.bankLabel(connection) == "C6 BANK")
    }

    @Test("A card-only proxy connection says what it actually knows")
    @MainActor
    func cardOnlyProxyKeepsConnectorName() {
        let connection = Self.connection(institutionId: "200", name: "MeuPluggy")
        let source = StubSource(
            connectionList: [connection],
            accountList: [Self.account(connection.id, type: .creditCard, name: "platinum")]
        )
        #expect(source.bankLabel(connection) == "MeuPluggy")
    }

    @Test("Another connection's accounts cannot name this one")
    @MainActor
    func accountsDoNotLeakAcrossConnections() {
        let nubank = Self.connection(institutionId: "200", name: "MeuPluggy")
        let other = Self.connection(institutionId: "200", name: "MeuPluggy")
        let source = StubSource(
            connectionList: [nubank, other],
            accountList: [
                Self.account(
                    other.id, type: .checking,
                    name: "Nu Pagamentos S.A. - Instituição de Pagamento"
                ),
            ]
        )
        // A second bank arrives as a second connection, so the filter by
        // connectionId is what keeps two proxied banks from borrowing each
        // other's name.
        #expect(source.bankLabel(nubank) == "MeuPluggy")
        #expect(source.bankLabel(other) == "Nu Pagamentos S.A.")
    }
}
