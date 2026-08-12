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

    /// Same shape, for the first of the four Edge Function actions (v30).
    ///
    /// The falsifiable assertion is again a re-read: `ReviewScreen` loads its
    /// payload in `.task`, so leaving 9a and coming back asks the provider
    /// afresh. Unwired, the suggestion is still there — `ReviewView` animates the
    /// row away out of its own local `resolved` set either way, which is exactly
    /// why "the row vanished" is not what this checks.
    func testTrackingASuggestionReachesTheProvider() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-review"]
        app.launch()

        let track = app.buttons["Track it"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 15), "review must offer Track it")
        let before = app.buttons.matching(identifier: "Track it").count
        XCTAssertGreaterThan(before, 0, "the fixtures should ship with suggestions")

        track.tap()

        // R4 suggestions ask monthly/annual before confirming; R3 never does,
        // because three date-aligned charges already measured the cadence. The
        // fixtures' first suggestion is R3, so this is a guard rather than a step.
        let monthly = app.buttons["Monthly"].firstMatch
        if monthly.waitForExistence(timeout: 2) { monthly.tap() }

        // Out of 9a and back in, so the list is read from the provider again.
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
