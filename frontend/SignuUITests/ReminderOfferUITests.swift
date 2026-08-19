import XCTest

@MainActor
final class ReminderOfferUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func review(_ app: XCUIApplication) {
        app.launchArguments = ["--shell-review", "--fresh-reminder-offer"]
        app.launch()
        XCTAssertTrue(app.buttons["Track it"].firstMatch.waitForExistence(timeout: 15),
                      "the review screen must list suggestions")
    }

    func testFirstConfirmationOffersAReminder() {
        let app = XCUIApplication()
        review(app)

        app.buttons["Track it"].firstMatch.tap()

        let confirmation = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "is now tracked")
        ).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5),
                      "a confirmed suggestion must acknowledge itself in place")
        XCTAssertTrue(app.staticTexts["Want a heads-up before it renews?"].exists,
                      "the first confirmation must offer a reminder")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "22b-offer"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Remind me")
        ).firstMatch.tap()

        XCTAssertFalse(app.staticTexts["Want a heads-up before it renews?"].waitForExistence(timeout: 2),
                       "answering must end the offer")
        XCTAssertTrue(confirmation.exists, "the confirmation itself stays")

        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "22b-collapsed"
        after.lifetime = .keepAlways
        add(after)
    }

    func testDecliningEndsTheOfferToo() {
        let app = XCUIApplication()
        review(app)
        app.buttons["Track it"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Want a heads-up before it renews?"].waitForExistence(timeout: 5))

        app.buttons["No thanks"].tap()
        XCTAssertFalse(app.staticTexts["Want a heads-up before it renews?"].waitForExistence(timeout: 2),
                       "declining must end the offer")
    }

    func testOnlyTheFirstConfirmationOffers() {
        let app = XCUIApplication()
        review(app)

        app.buttons["Track it"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Want a heads-up before it renews?"].waitForExistence(timeout: 5))
        app.buttons["No thanks"].tap()

        app.buttons["Track it"].firstMatch.tap()
        let monthly = app.buttons["Monthly"].firstMatch
        if monthly.waitForExistence(timeout: 3) { monthly.tap() }

        let confirmations = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "is now tracked")
        )
        XCTAssertTrue(confirmations.count >= 2 || confirmations.firstMatch.waitForExistence(timeout: 5),
                      "both confirmations should be acknowledged")
        XCTAssertFalse(app.staticTexts["Want a heads-up before it renews?"].exists,
                       "the offer is made once, not once per confirmation")
    }
}
