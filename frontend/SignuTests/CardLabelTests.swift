import Testing
import Foundation
@testable import Signu


@Suite("Card label (v59)")
@MainActor
struct CardLabelTests {

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

    private static func account(brand: String?, last4: String) -> BankAccount {
        BankAccount(
            id: UUID(), connectionId: UUID(), type: .creditCard, brand: brand,
            last4: last4, officialName: "platinum", nickname: nil, status: .active
        )
    }

    private static func charge(transactionId: UUID?, storedLabel: String) -> Charge {
        Charge(
            id: UUID(), runId: UUID(), transactionId: transactionId,
            date: Date(timeIntervalSince1970: 1_779_000_000), amount: 44.22,
            currency: "BRL", cardLabel: storedLabel
        )
    }

    private static func source(
        charge: Charge, account: BankAccount?
    ) -> (StubSource, Charge) {
        var source = StubSource()
        if let account, let transactionId = charge.transactionId {
            source.accountList = [account]
            source.transactionAccountMap = [transactionId: account.id]
        }
        source.chargeList = [charge]
        return (source, charge)
    }

    @Test("the card is derived from the account when the column is null")
    func derivedFromAccount() {
        let account = Self.account(brand: "MASTERCARD", last4: "4321")
        let (source, charge) = Self.source(
            charge: Self.charge(transactionId: UUID(), storedLabel: ""), account: account
        )
        #expect(source.derivedCardLabel(for: charge) == "Master 4321")
    }

    @Test("a stored snapshot wins over the account")
    func storedWins() {
        let account = Self.account(brand: "MASTERCARD", last4: "4321")
        let (source, charge) = Self.source(
            charge: Self.charge(transactionId: UUID(), storedLabel: "Visa 4821"), account: account
        )
        #expect(source.derivedCardLabel(for: charge) == "Visa 4821")
    }

    @Test("an unknown brand is title-cased rather than guessed at")
    func unknownBrand() {
        let account = Self.account(brand: "elo", last4: "7730")
        let (source, charge) = Self.source(
            charge: Self.charge(transactionId: UUID(), storedLabel: ""), account: account
        )
        #expect(source.derivedCardLabel(for: charge) == "Elo 7730")
    }

    @Test("a charge with no brand cannot be named")
    func noBrand() {
        let account = Self.account(brand: nil, last4: "3816")
        let (source, charge) = Self.source(
            charge: Self.charge(transactionId: UUID(), storedLabel: ""), account: account
        )
        #expect(source.derivedCardLabel(for: charge) == nil)
    }

    @Test("a charge whose raw transaction is gone cannot be named")
    func deletedTransaction() {
        let (source, charge) = Self.source(
            charge: Self.charge(transactionId: nil, storedLabel: ""), account: nil
        )
        #expect(source.derivedCardLabel(for: charge) == nil)
    }


    private static func run(_ interval: BillingInterval) -> SubscriptionRun {
        SubscriptionRun(
            id: UUID(), subscriptionId: UUID(),
            startDate: Date(timeIntervalSince1970: 1_770_000_000), endDate: nil,
            cancelledDate: nil, billingInterval: interval, status: .active,
            detectedBy: .r1, nextExpectedDate: Date(timeIntervalSince1970: 1_781_000_000)
        )
    }

    @Test("the separator only appears when there is something after it")
    func separatorIsPartOfTheLabel() {
        let named = Self.source(
            charge: Self.charge(transactionId: UUID(), storedLabel: ""),
            account: Self.account(brand: "MASTERCARD", last4: "4321")
        )
        #expect(named.0.intervalAndCard(Self.run(.monthly), named.1) == "Monthly · Master 4321")

        let unnamed = Self.source(
            charge: Self.charge(transactionId: nil, storedLabel: ""), account: nil
        )
        #expect(unnamed.0.intervalAndCard(Self.run(.monthly), unnamed.1) == "Monthly")
        #expect(unnamed.0.intervalAndCard(Self.run(.annual), unnamed.1) == "Annual")
    }
}
