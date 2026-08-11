import XCTest

/// The auth gate, driven through the UI.
///
/// Everything here runs against `MockSessionProvider`, which is built for exactly
/// this: no SDK, no tokens, no networking, and error injection that rides on the
/// input rather than a debug toggle — so triggering a failure is the same gesture a
/// real user makes. That makes these deterministic and offline, unlike the live
/// paths, which need a real account and cannot be a CI gate.
///
/// XCTest rather than Swift Testing: `XCUIApplication` has no Swift Testing entry
/// point, and UI tests are the one place the older framework is still the answer.
///
/// Element queries were written against a dumped accessibility tree, not guessed.
/// Two things that tree settled: 16a's entry is labelled "Already have an account?
/// Sign in" rather than "Sign in", and 17a's fields carry only a placeholder, no
/// label — so they are reached as *the* text field and *the* secure field on that
/// screen, of which there is exactly one each.
/// `@MainActor` because XCUIApplication and XCUIElement are: driving the UI is
/// main-actor work, and the project is in the Swift 6 language mode.
@MainActor
final class AuthGateUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    // MARK: - 17a

    func testWrongPasswordShowsTheErrorBanner() {
        // The error surfacing from #21 has never been exercised end to end. Any
        // password other than MockInput.password is wrong.
        let app = signInScreen()
        fillCredentials(app, email: "rafael.souza@example.com", password: "wrongpassword1A")
        app.buttons["Sign in"].tap()

        // Asserted on the copy, because the failure that matters is the screen
        // going quiet — a tap that neither signs in nor says why.
        XCTAssertTrue(text(app, startingWith: "Couldn't sign in").waitForExistence(timeout: 5),
                      "17a must surface a failed sign-in, never fail silently")
    }

    func testUnconfirmedEmailIsADistinctState() {
        // `unverified@` yields emailNotConfirmed rather than invalidCredentials.
        // Folding the two together would tell someone to check a password that was
        // correct, which is why SessionAuthError keeps the case separate.
        let app = signInScreen()
        fillCredentials(app, email: "unverified@example.com", password: "Signu123")
        app.buttons["Sign in"].tap()

        XCTAssertTrue(text(app, startingWith: "Your email isn't confirmed").waitForExistence(timeout: 5),
                      "the unconfirmed state must read differently from a wrong password")
        XCTAssertFalse(text(app, startingWith: "Couldn't sign in").exists,
                       "telling this user to check their password would be actively wrong")
    }

    func testCorrectPasswordReachesTheAppShell() {
        let app = signInScreen()
        fillCredentials(app, email: "rafael.souza@example.com", password: "Signu123")
        app.buttons["Sign in"].tap()

        // The tab bar exists only inside the shell, so it is the honest signal that
        // the gate flipped rather than the button merely having been tapped.
        XCTAssertTrue(app.buttons["Subs"].waitForExistence(timeout: 10),
                      "a correct password must land in the app shell")
    }

    // MARK: - v19 sign-out

    func testSignOutReturnsToWelcome() {
        // No confirmation by contract: nothing is lost and signing back in is one
        // tap. What must hold is that the gate returns to 16a rather than leaving a
        // signed-out user sitting inside the shell.
        let app = launch("--shell-settings")

        let signOut = app.buttons["Sign out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10), "Settings must offer sign-out")
        signOut.tap()

        // 16a's own affordance, unreachable from inside the shell — and the reason
        // the contract can skip a confirmation: a Google-only user who signs out
        // lands with Continue with Google right there.
        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 10),
                      "signing out must land on 16a")
        XCTAssertFalse(app.buttons["Subs"].exists, "the shell must be gone, not merely covered")
    }

    // MARK: - Helpers

    private func signInScreen() -> XCUIApplication {
        let app = launch("--gate=welcome")
        let entry = app.buttons["Already have an account? Sign in"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "16a must offer a way to sign in")
        entry.tap()
        return app
    }

    /// 17a carries exactly one text field and one secure field, and neither has an
    /// accessibility label — only a placeholder, which is copy and may change.
    private func fillCredentials(_ app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields.element
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "17a must have an email field")
        type(email, into: emailField, in: app)

        let passwordField = app.secureTextFields.element
        XCTAssertTrue(passwordField.exists, "17a must have a password field")
        type(password, into: passwordField, in: app)
    }

    /// Waits for the keyboard before typing. On a freshly booted simulator — which
    /// is what CI always has — `typeText` otherwise fails with "Neither element nor
    /// any descendant has keyboard focus", as a flake rather than a real defect.
    private func type(_ value: String, into field: XCUIElement, in app: XCUIApplication) {
        field.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 10),
                      "no keyboard attached, so typing would flake rather than test anything")
        field.typeText(value)
    }

    /// `matching`, not `containing`: the latter tests an element's *descendants*, so
    /// it never matches a leaf StaticText.
    private func text(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }
}
