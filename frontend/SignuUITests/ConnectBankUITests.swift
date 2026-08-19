import XCTest

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

        let simulate = app.buttons["Simulate success"]
        XCTAssertTrue(simulate.waitForExistence(timeout: 10),
                      "Connect a bank did not open the connect flow — the action is not wired")
        simulate.tap()

        XCTAssertTrue(newBank.waitForExistence(timeout: 10),
                      "the connected bank did not reach the provider, or the screen did not re-read")
    }

    func testReconnectOpensTheFlowForAnExistingBank() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-settings"]
        app.launch()

        let bank = app.staticTexts["Demo Bank"].firstMatch
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
