import Testing
import Foundation
@testable import Signu

// "Monthly · Master 2049" (v59), and the dangling separator it replaces.
//
// The rows interpolated `charge.card_label` directly. That column has a reader and NO
// writer — the engine hardcodes `card_label: null` in `detection.ts` — so every charge
// in production carries null and the subtitle rendered "Monthly · " with punctuation
// drawn around an absence.

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
            date: Date(timeIntervalSince1970: 1_779_000_000), amount: 34.33,
            currency: "BRL", cardLabel: storedLabel
        )
    }

    /// A charge whose transaction resolves to `account`, as the live provider maps it.
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
        // Production's shape: card_label null, and a Mastercard ending 2049 behind the
        // transaction. The app already holds both halves.
        let account = Self.account(brand: "MASTERCARD", last4: "2049")
        let (source, charge) = Self.source(
            charge: Self.charge(transactionId: UUID(), storedLabel: ""), account: account
        )
        #expect(source.derivedCardLabel(for: charge) == "Master 2049")
    }

    @Test("a stored snapshot wins over the account")
    func storedWins() {
        // `card_label` is documented as a snapshot at billing time. If the engine ever
        // writes one it describes the card as it WAS, which outranks the account as it
        // is now — a card replaced since would otherwise rewrite history.
        let account = Self.account(brand: "MASTERCARD", last4: "2049")
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
        // A checking account has no card brand, so there is no card to name — and
        // "Account 3816" would be inventing one.
        let account = Self.account(brand: nil, last4: "3816")
        let (source, charge) = Self.source(
            charge: Self.charge(transactionId: UUID(), storedLabel: ""), account: account
        )
        #expect(source.derivedCardLabel(for: charge) == nil)
    }

    @Test("a charge whose raw transaction is gone cannot be named")
    func deletedTransaction() {
        // `transaction_id = NULL` is by design once raw data is deleted, so this is an
        // ordinary state and not an error.
        let (source, charge) = Self.source(
            charge: Self.charge(transactionId: nil, storedLabel: ""), account: nil
        )
        #expect(source.derivedCardLabel(for: charge) == nil)
    }

    // MARK: - The subtitle, which is where the dangling separator showed

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
            account: Self.account(brand: "MASTERCARD", last4: "2049")
        )
        #expect(named.0.intervalAndCard(Self.run(.monthly), named.1) == "Monthly · Master 2049")

        // The reported bug: this produced "Monthly · " — punctuation around nothing.
        let unnamed = Self.source(
            charge: Self.charge(transactionId: nil, storedLabel: ""), account: nil
        )
        #expect(unnamed.0.intervalAndCard(Self.run(.monthly), unnamed.1) == "Monthly")
        #expect(unnamed.0.intervalAndCard(Self.run(.annual), unnamed.1) == "Annual")
    }
}
