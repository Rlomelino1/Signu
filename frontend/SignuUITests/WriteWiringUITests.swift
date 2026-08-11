import XCTest

/// That the write actions are actually WIRED.
///
/// This is the gap the unit tests cannot reach and the one that has already bitten:
/// every state-changing control in this app called a closure no caller supplied, so
/// the interface looked complete and changed nothing. A provider test passes happily
/// while `AppShellView` leaves the closure at its default.
///
/// Two things this test deliberately does NOT assert, because both pass unwired:
///
///  * "the review row disappeared" — `ReviewView` inserts the suggestion into a
///    local `resolved` set and animates it away regardless of what the closure does,
///    so that would test the animation.
///  * "Settings shows a dismissed row" — the fixtures ship with dismissed rows
///    already, so the section is never empty to begin with.
///
/// What requires the write to have happened is the dismissed COUNT going up by one,
/// measured before and after, because that list is re-read from the provider.
///
/// `@MainActor` because XCUIApplication is.
@MainActor
final class WriteWiringUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Rows reading "Not a subscription · <date>" — the contract's dismissed-row copy.
    private func dismissedRowCount(in app: XCUIApplication) -> Int {
        app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Not a subscription ·"))
            .count
    }

    func testDismissingASuggestionReachesTheProvider() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        // Baseline, from the same surface the assertion will re-read.
        let dismissedHeader = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Dismissed suggestions")
        ).firstMatch
        XCTAssertTrue(dismissedHeader.waitForExistence(timeout: 15),
                      "Settings must list dismissed suggestions")
        let before = dismissedRowCount(in: app)
        XCTAssertGreaterThan(before, 0, "the fixtures should ship with dismissed rows")

        // Home → the review pill → 9a.
        app.buttons["Home"].tap()
        let reviewPill = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Possible subscriptions detected")
        ).firstMatch
        XCTAssertTrue(reviewPill.waitForExistence(timeout: 10), "Home must offer Review")
        reviewPill.tap()

        let dismiss = app.buttons["Not a subscription"].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10), "review must offer a dismiss action")
        dismiss.tap()

        // Back out and re-read Settings.
        app.buttons["Back"].firstMatch.tap()
        let settingsTab = app.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()
        XCTAssertTrue(dismissedHeader.waitForExistence(timeout: 10))

        // The falsifiable assertion. Unwired, this count is unchanged.
        XCTAssertEqual(
            dismissedRowCount(in: app), before + 1,
            "the dismissed subscription did not reach the provider — the action is not wired"
        )
    }
}
