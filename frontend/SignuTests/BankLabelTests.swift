import Testing
import Foundation
@testable import Signu


@Suite("Bank label derivation (v43)")
struct BankLabelTests {


    @Test("A real connector keeps its name, accounts notwithstanding")
    func realConnectorIsUntouched() {
        let label = BankLabel.resolve(
            institutionId: "212",
            institutionName: "Nubank",
            proxiedAccountNames: ["Nu Pagamentos S.A. - Instituição de Pagamento (Conta Pré-paga)"]
        )
        #expect(label == "Nubank")
    }


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
        #expect(source.bankLabel(nubank) == "MeuPluggy")
        #expect(source.bankLabel(other) == "Nu Pagamentos S.A.")
    }
}
