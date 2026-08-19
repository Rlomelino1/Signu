import XCTest

@MainActor
final class PasswordRowUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchSettings(_ extra: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"] + extra
        app.launch()
        return app
    }

    func testTappingThePasswordRowShowsTheSentStateWithACountdown() {
        let app = launchSettings()

        let row = app.buttons["Change password"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the mock profile has a password identity, so the row offers to change it")
        row.tap()

        let sent = text(app, startingWith: "Check ")
        XCTAssertTrue(sent.waitForExistence(timeout: 5), "the row must confirm the send")
        XCTAssertTrue(sent.label.contains("@"), "the confirmation must name the address")

        XCTAssertTrue(countdown(in: app).waitForExistence(timeout: 5),
                      "the cooldown must be visible, or a second tap fails silently")
    }

    func testTheCooldownSurvivesLeavingTheTab() {
        let app = launchSettings()

        let row = app.buttons["Change password"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let before = seconds(from: countdown(in: app))
        XCTAssertNotNil(before, "the countdown must render a number to compare")

        app.buttons["Home"].tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2), "Home must not render the Settings row")
        app.buttons["Settings"].tap()

        let after = countdown(in: app)
        XCTAssertTrue(after.waitForExistence(timeout: 5),
                      "the sent state must survive a tab switch, not reset to an untapped row")
        XCTAssertFalse(row.exists, "the row must not offer to send again mid-cooldown")

        if let before, let after = seconds(from: after) {
            XCTAssertLessThanOrEqual(after, before,
                                     "time spent away must still burn down the cooldown")
        }
    }

    func testTheSentStateIsForgottenOnceExpiredAndTheUserLeaves() {
        let app = launchSettings("--settings-password-sent=expired")

        let resend = app.buttons["Send another link"]
        XCTAssertTrue(resend.waitForExistence(timeout: 10),
                      "an expired cooldown must offer the resend")
        XCTAssertFalse(app.buttons["Change password"].exists,
                       "the row is still in its sent state before leaving")

        app.buttons["Home"].tap()
        app.buttons["Settings"].tap()

        let row = app.buttons["Change password"]
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "an expired sent state must be forgotten once the user leaves")
        XCTAssertFalse(text(app, startingWith: "Check ").exists,
                       "the stale confirmation must be gone, not merely scrolled past")
        XCTAssertFalse(resend.exists, "and so must the resend it offered")
    }

    func testGoogleOnlyAccountIsOfferedToSetAPassword() {
        let app = launchSettings("--settings-google-only")

        let row = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Set a password"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "a Google-only identity must be offered to SET a password")
        XCTAssertFalse(app.buttons["Change password"].exists,
                       "offering to change a password that does not exist sends the user nowhere")
    }


    private func countdown(in app: XCUIApplication) -> XCUIElement {
        text(app, startingWith: "Resend available in")
    }

    private func text(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }

    private func seconds(from element: XCUIElement) -> Int? {
        guard element.exists else { return nil }
        let digits = element.label.components(separatedBy: CharacterSet.decimalDigits.inverted)
        return digits.compactMap(Int.init).first
    }
}
