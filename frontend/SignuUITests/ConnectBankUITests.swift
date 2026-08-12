import XCTest

/// That connecting a bank is wired end to end — the button that has been inert
/// since the empty state was designed.
///
/// The mock provider reports its connect session as `simulated`, so the flow
/// renders a labelled stand-in instead of the Pluggy widget: there is no bank to
/// sign in to in a test build, and a web view that fails to load would test
/// nothing. Everything on either side of the widget is real — the provider call,
/// the registration, the cache invalidation and the rebuild that makes the new
/// bank appear.
///
/// The falsifiable assertion is the new bank row in Settings. Unwired, tapping
/// "Connect a bank" opens nothing and the row never arrives.
@MainActor
final class ConnectBankUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testConnectingABankReachesTheProvider() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let connect = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Connect a bank")
        ).firstMatch
        XCTAssertTrue(connect.waitForExistence(timeout: 15), "Settings must offer Connect a bank")

        let newBank = app.staticTexts["Simulated Bank"]
        XCTAssertFalse(newBank.exists, "the fixtures should not ship with the simulated bank")

        connect.tap()

        // The flow opened at all — this alone fails when the action is unwired.
        let simulate = app.buttons["Simulate success"]
        XCTAssertTrue(simulate.waitForExistence(timeout: 10),
                      "Connect a bank did not open the connect flow — the action is not wired")
        simulate.tap()

        XCTAssertTrue(newBank.waitForExistence(timeout: 10),
                      "the connected bank did not reach the provider, or the screen did not re-read")
    }

    /// The same flow, opened on an existing link. 12b's Reconnect and Home's
    /// needs-action banner are re-authentication rather than a new bank, and
    /// Pluggy needs the item id on the token itself for that — so the two paths
    /// are one flow with an id, and this pins the id-carrying one.
    func testReconnectOpensTheFlowForAnExistingBank() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        // Itaú ships needing action, which is what renders the Reconnect button.
        let bank = app.staticTexts["Itaú"].firstMatch
        XCTAssertTrue(bank.waitForExistence(timeout: 15))
        bank.tap()

        let reconnect = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Reconnect")
        ).firstMatch
        XCTAssertTrue(reconnect.waitForExistence(timeout: 10),
                      "a connection needing action must offer Reconnect")
        reconnect.tap()

        XCTAssertTrue(app.buttons["Simulate success"].waitForExistence(timeout: 10),
                      "Reconnect did not open the connect flow — the action is not wired")
    }
}
