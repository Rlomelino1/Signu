import XCTest

/// v19's password row, and specifically the one property no unit test can reach.
///
/// The cooldown lives in a `PasswordLinkState` owned by `AppShellView` rather than
/// in `SettingsView`, because `switch selectedTab` destroys the branch it is not
/// rendering. That claim is structural — it is about SwiftUI view identity, not
/// about any function's return value — so the only thing that can actually check it
/// is a test that changes tab and comes back. PR #24 said as much and deferred it;
/// this is that test.
/// `@MainActor` because XCUIApplication and XCUIElement are: driving the UI is
/// main-actor work, and the project is in the Swift 6 language mode.
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

        // Unhedged copy, unlike 17d's "If an account exists for …": from Settings
        // the session proves the address, so the row may state it directly.
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

        // Leave and return. Held in SettingsView this reset to the untapped row,
        // and Supabase rate-limits the endpoint at ~60s while the send swallows its
        // errors by contract — so a forgetful cooldown means a tap that does nothing
        // and says nothing.
        app.buttons["Home"].tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2), "Home must not render the Settings row")
        app.buttons["Settings"].tap()

        let after = countdown(in: app)
        XCTAssertTrue(after.waitForExistence(timeout: 5),
                      "the sent state must survive a tab switch, not reset to an untapped row")
        XCTAssertFalse(row.exists, "the row must not offer to send again mid-cooldown")

        // A timestamp, not a counter: elapsed time on the Home tab still counts. A
        // decrementing counter would come back at or above where it left off,
        // because nothing was alive to tick it.
        if let before, let after = seconds(from: after) {
            XCTAssertLessThanOrEqual(after, before,
                                     "time spent away must still burn down the cooldown")
        }
    }

    /// v48. The other half of the tab-switch property above: the cooldown must
    /// survive leaving *while it is running*, and the sent state must NOT survive
    /// leaving once it has expired.
    ///
    /// Nothing cleared it before this, so one tap left "Check your email for a link"
    /// and a live Resend standing for the rest of the process lifetime — describing a
    /// 120-second window that had long since closed.
    ///
    /// Backdated by the harness rather than waited out: a test that slept two
    /// minutes to assert this would be a test nobody runs.
    func testTheSentStateIsForgottenOnceExpiredAndTheUserLeaves() {
        let app = launchSettings("--settings-password-sent=expired")

        // Expired, so the row is in its sent state with the resend already offered
        // — the state the user was left stuck in.
        let resend = app.buttons["Send another link"]
        XCTAssertTrue(resend.waitForExistence(timeout: 10),
                      "an expired cooldown must offer the resend")
        XCTAssertFalse(app.buttons["Change password"].exists,
                       "the row is still in its sent state before leaving")

        app.buttons["Home"].tap()
        app.buttons["Settings"].tap()

        // Back to the original row. The harness arms once per launch, so this is the
        // reset rather than a re-armed fixture.
        let row = app.buttons["Change password"]
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "an expired sent state must be forgotten once the user leaves")
        XCTAssertFalse(text(app, startingWith: "Check ").exists,
                       "the stale confirmation must be gone, not merely scrolled past")
        XCTAssertFalse(resend.exists, "and so must the resend it offered")
    }

    func testGoogleOnlyAccountIsOfferedToSetAPassword() {
        // "Set" not "Change" — the same distinction v11 made naming 17d, because a
        // Google-first account has no old password to change.
        let app = launchSettings("--settings-google-only")

        // The subtitle is folded into the button's accessibility label
        // ("Set a password, You sign in with Google. …"), so this matches a prefix
        // rather than the whole string.
        let row = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Set a password"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "a Google-only identity must be offered to SET a password")
        XCTAssertFalse(app.buttons["Change password"].exists,
                       "offering to change a password that does not exist sends the user nowhere")
    }

    // MARK: - Helpers

    private func countdown(in app: XCUIApplication) -> XCUIElement {
        text(app, startingWith: "Resend available in")
    }

    /// `matching`, not `containing`: the latter tests an element's *descendants*, so
    /// it never matches a leaf StaticText.
    private func text(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }

    /// The integer inside "Resend available in 116s".
    private func seconds(from element: XCUIElement) -> Int? {
        guard element.exists else { return nil }
        let digits = element.label.components(separatedBy: CharacterSet.decimalDigits.inverted)
        return digits.compactMap(Int.init).first
    }
}
