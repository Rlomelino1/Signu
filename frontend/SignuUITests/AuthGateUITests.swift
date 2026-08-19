import XCTest

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


    func testWrongPasswordShowsTheErrorBanner() {
        let app = signInScreen()
        fillCredentials(app, email: "rafael.souza@example.com", password: "wrongpassword1A")
        app.buttons["Sign in"].tap()

        XCTAssertTrue(text(app, startingWith: "Couldn't sign in").waitForExistence(timeout: 5),
                      "17a must surface a failed sign-in, never fail silently")
    }

    func testUnconfirmedEmailIsADistinctState() {
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

        XCTAssertTrue(app.buttons["Subs"].waitForExistence(timeout: 10),
                      "a correct password must land in the app shell")
    }


    func testSignOutReturnsToWelcome() {
        let app = launch("--shell-settings")

        let signOut = app.buttons["Sign out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10), "Settings must offer sign-out")
        signOut.tap()

        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 10),
                      "signing out must land on 16a")
        XCTAssertFalse(app.buttons["Subs"].exists, "the shell must be gone, not merely covered")
    }


    private func signInScreen() -> XCUIApplication {
        let app = launch("--gate=welcome")
        let entry = app.buttons["Already have an account? Sign in"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "16a must offer a way to sign in")
        entry.tap()
        return app
    }

    private func fillCredentials(_ app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields.element
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "17a must have an email field")
        type(email, into: emailField, in: app)

        let passwordField = app.secureTextFields.element
        XCTAssertTrue(passwordField.exists, "17a must have a password field")
        type(password, into: passwordField, in: app)
    }

    private func type(_ value: String, into field: XCUIElement, in app: XCUIApplication) {
        field.tap()
        _ = app.keyboards.element.waitForExistence(timeout: 30)
        field.typeText(value)

        if let typed = field.value as? String {
            XCTAssertFalse(typed.isEmpty, "the field did not take the text")
        }
    }

    private func text(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }
}
