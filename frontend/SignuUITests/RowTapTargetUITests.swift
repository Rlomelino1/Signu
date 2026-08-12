import XCTest

/// That rows are tappable in their MIDDLE, not only on their words.
///
/// A `Button` with `.buttonStyle(.plain)` hit-tests only what it draws. Every list
/// row in this app draws two text columns with a `Spacer` between them, so the gap
/// in the middle and the padding above and below it were dead: a tap that landed
/// there did nothing at all, which reads as a broken app rather than as a missed
/// target.
///
/// **Each test taps a raw centre coordinate rather than calling `tap()` on the
/// element.** `XCUIElement.tap()` asks XCTest for *a* hittable point and will
/// happily find the label text at the row's left edge — which passes with the bug
/// present. `coordinate(withNormalizedOffset:)` taps exactly where the dead zone
/// was, so these fail without `.contentShape(Rectangle())` and pass with it.
///
/// One test per fixed row, deliberately not a single loop: the fix is per-row
/// because the rows are built differently, and a shared helper would hide which
/// one regressed.
@MainActor
final class RowTapTargetUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Taps the geometric centre of an element, ignoring hittability heuristics.
    private func tapCentre(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    // MARK: - SignuRow, the shared row (Home, Subs groups, Connection detail)

    func testHomeSubscriptionRowOpensDetailFromItsMiddle() {
        let app = XCUIApplication()
        app.launch()

        let row = button(app, containing: "Spotify")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Home must list subscriptions")
        tapCentre(row)

        // Mark cancelled only exists on the detail screen (10a).
        XCTAssertTrue(app.buttons["Mark cancelled"].waitForExistence(timeout: 10),
                      "the middle of a Home row is dead — SignuRow needs its content shape")
    }

    func testSubsGroupRowOpensDetailFromItsMiddle() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-subs"]
        app.launch()

        let row = button(app, containing: "Netflix")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the Subs tab must list subscriptions")
        tapCentre(row)

        XCTAssertTrue(app.buttons["Mark cancelled"].waitForExistence(timeout: 10),
                      "the middle of a Subs group row is dead")
    }

    // MARK: - Hand-built rows

    func testSubsSuggestedRowOpensReviewFromItsMiddle() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-subs"]
        app.launch()

        // The SUGGESTED section's rows carry the green evidence line, which is why
        // they are hand-built rather than SignuRow.
        let row = button(app, containing: "ChatGPT Plus")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the Subs tab must list suggestions")
        tapCentre(row)

        XCTAssertTrue(app.buttons["Track it"].firstMatch.waitForExistence(timeout: 10),
                      "the middle of a suggested row is dead")
    }

    func testSubsInactiveRowOpensDetailFromItsMiddle() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-subs", "--subs-inactive"]
        app.launch()

        // Inactive rows are hand-built too: the right rail is chip-over-date.
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Ended", "Cancelled")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the inactive filter must list rows")
        tapCentre(row)

        // Dead subscriptions have no reminder or cancel action, so the back
        // chevron standing alone over a hero is the detail screen's fingerprint.
        XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout: 10),
                      "the middle of an inactive row is dead")
    }

    func testSettingsBankRowOpensConnectionDetailFromItsMiddle() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let row = button(app, containing: "Nubank")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Settings must list banks")
        tapCentre(row)

        // Case-insensitive: `OverlineText` renders section headers uppercased, so
        // the accessibility label is "CARDS ON THIS LINK".
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Cards on this link")
        ).firstMatch.waitForExistence(timeout: 10), "the middle of a bank row is dead")
    }

    // MARK: - Labels with a drawn surface
    //
    // These were expected to be fine — their labels paint a card or a tint across
    // the whole row, which reads like a hit area. It is not one: `.background(_,
    // in:)` paints behind the content and does not extend a plain button's target.
    // Found by tapping a real coordinate rather than by reading the code, which
    // had concluded the opposite.

    func testDeleteAccountRowOpensTheSheetFromItsMiddle() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let row = button(app, containing: "Delete account")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Settings must offer Delete account")
        // The row sits at the far end of the scroll, and Delete account is
        // deliberately separated from the rest by the whole screen (12a).
        var scrolls = 0
        while !row.isHittable, scrolls < 8 {
            app.swipeUp()
            scrolls += 1
        }
        tapCentre(row)

        // The sheet's header, not its button: 14a's button is disabled until
        // "DELETE" is typed, so asserting on it would conflate "the sheet opened"
        // with "the sheet is ready to fire".
        XCTAssertTrue(app.staticTexts["Delete your account?"].waitForExistence(timeout: 10),
                      "the delete-account row did not open 14a")
    }

    func testReviewPillOpensReviewFromItsMiddle() {
        let app = XCUIApplication()
        app.launch()

        let pill = button(app, containing: "Possible subscriptions detected")
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "Home must offer the review pill")
        tapCentre(pill)

        XCTAssertTrue(app.buttons["Track it"].firstMatch.waitForExistence(timeout: 10),
                      "the middle of the review pill is dead")
    }

    func testConnectionSummaryRowOpensTheAttributedListFromItsMiddle() {
        // The load-bearing eyes-open surface (13a): the only pre-delete view of
        // what "Delete them too" takes. Reaching it must not depend on hitting
        // the words.
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let bank = button(app, containing: "Nubank")
        XCTAssertTrue(bank.waitForExistence(timeout: 15))
        bank.tap()

        let summary = button(app, containing: "subscriptions found via this bank")
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "12b must offer the summary row")
        tapCentre(summary)

        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Removing this bank link decides")
        ).firstMatch.waitForExistence(timeout: 10), "the middle of the summary row is dead")
    }

    func testRemoveBankHistoryChoiceSelectsFromItsMiddle() {
        // 12c's radio decides whether charge history is erased. A choice the user
        // believes they made, that did not register, is the worst case for this
        // bug — the destructive button below it restates the choice, so this
        // asserts on that restatement rather than on the radio's own rendering.
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let bank = button(app, containing: "Nubank")
        XCTAssertTrue(bank.waitForExistence(timeout: 15))
        bank.tap()

        let remove = app.buttons["Remove this bank link"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()

        XCTAssertTrue(app.buttons["Remove link, keep history"].waitForExistence(timeout: 10),
                      "keep-history is pre-selected by contract")

        let deleteToo = button(app, containing: "Delete them too")
        XCTAssertTrue(deleteToo.waitForExistence(timeout: 5))
        tapCentre(deleteToo)

        XCTAssertTrue(app.buttons["Remove link and history"].waitForExistence(timeout: 5),
                      "the middle of the history choice is dead — the radio did not move")
    }

    func testRestoreStillWinsInsideTheDismissedRow() {
        // The nested-button case, and the reason the fix is not applied blanket.
        // A dismissed row is deliberately NOT a button: if it were, giving it a
        // content shape could let the parent swallow the taps meant for Restore.
        // This is the regression guard for that — Restore must still restore.
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let dismissedRows = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Not a subscription ·")
        )
        XCTAssertTrue(dismissedRows.firstMatch.waitForExistence(timeout: 15))
        let before = dismissedRows.count

        let restore = app.buttons["Restore"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10), "dismissed rows must offer Restore")
        restore.tap()

        // The row leaves the list, which only happens if the child button got the
        // tap. Polled rather than waited on an element, because the assertion is
        // about a COUNT falling and `waitForExistence` cannot express that.
        let deadline = Date().addingTimeInterval(10)
        while dismissedRows.count == before, Date() < deadline { usleep(200_000) }
        XCTAssertEqual(dismissedRows.count, before - 1,
                       "Restore was swallowed — the parent row is taking taps meant for the child")
    }
}
