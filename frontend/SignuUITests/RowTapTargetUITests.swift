import XCTest

@MainActor
final class RowTapTargetUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func tapCentre(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }


    func testHomeSubscriptionRowOpensDetailFromItsMiddle() {
        let app = XCUIApplication()
        app.launch()

        let row = button(app, containing: "Spotify")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Home must list subscriptions")
        tapCentre(row)

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


    func testSubsSuggestedRowOpensReviewFromItsMiddle() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-subs"]
        app.launch()

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

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Ended", "Cancelled")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the inactive filter must list rows")
        tapCentre(row)

        XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout: 10),
                      "the middle of an inactive row is dead")
    }

    func testSettingsBankRowOpensConnectionDetailFromItsMiddle() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let row = button(app, containing: "Mock Bank")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Settings must list banks")
        tapCentre(row)

        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Cards on this link")
        ).firstMatch.waitForExistence(timeout: 10), "the middle of a bank row is dead")
    }


    func testDeleteAccountRowOpensTheSheetFromItsMiddle() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let row = button(app, containing: "Delete account")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Settings must offer Delete account")
        var scrolls = 0
        while !row.isHittable, scrolls < 8 {
            app.swipeUp()
            scrolls += 1
        }
        tapCentre(row)

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
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let bank = button(app, containing: "Mock Bank")
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
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let bank = button(app, containing: "Mock Bank")
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

        let deadline = Date().addingTimeInterval(10)
        while dismissedRows.count == before, Date() < deadline { usleep(200_000) }
        XCTAssertEqual(dismissedRows.count, before - 1,
                       "Restore was swallowed — the parent row is taking taps meant for the child")
    }
}
