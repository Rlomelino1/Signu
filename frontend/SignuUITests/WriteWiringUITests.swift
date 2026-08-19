import XCTest

@MainActor
final class WriteWiringUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func dismissedRowCount(in app: XCUIApplication) -> Int {
        app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Not a subscription ·"))
            .count
    }

    func testTrackingASuggestionReachesTheProvider() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-review"]
        app.launch()

        let track = app.buttons["Track it"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 15), "review must offer Track it")
        let before = app.buttons.matching(identifier: "Track it").count
        XCTAssertGreaterThan(before, 0, "the fixtures should ship with suggestions")

        track.tap()

        let monthly = app.buttons["Monthly"].firstMatch
        if monthly.waitForExistence(timeout: 2) { monthly.tap() }

        app.buttons["Back"].firstMatch.tap()
        let reviewPill = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Possible subscriptions detected")
        ).firstMatch
        XCTAssertTrue(reviewPill.waitForExistence(timeout: 10), "Home must still offer Review")
        reviewPill.tap()
        XCTAssertTrue(app.buttons["Track it"].firstMatch.waitForExistence(timeout: 10))

        XCTAssertEqual(
            app.buttons.matching(identifier: "Track it").count, before - 1,
            "the confirmed suggestion did not reach the provider — the action is not wired"
        )
    }

    func testDismissingASuggestionReachesTheProvider() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let dismissedHeader = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Dismissed suggestions")
        ).firstMatch
        XCTAssertTrue(dismissedHeader.waitForExistence(timeout: 15),
                      "Settings must list dismissed suggestions")
        let before = dismissedRowCount(in: app)
        XCTAssertGreaterThan(before, 0, "the fixtures should ship with dismissed rows")

        app.buttons["Home"].tap()
        let reviewPill = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Possible subscriptions detected")
        ).firstMatch
        XCTAssertTrue(reviewPill.waitForExistence(timeout: 10), "Home must offer Review")
        reviewPill.tap()

        let dismiss = app.buttons["Not a subscription"].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10), "review must offer a dismiss action")
        dismiss.tap()

        app.buttons["Back"].firstMatch.tap()
        let settingsTab = app.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()
        XCTAssertTrue(dismissedHeader.waitForExistence(timeout: 10))

        XCTAssertEqual(
            dismissedRowCount(in: app), before + 1,
            "the dismissed subscription did not reach the provider — the action is not wired"
        )
    }
}
