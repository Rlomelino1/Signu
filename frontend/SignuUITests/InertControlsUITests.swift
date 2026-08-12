import XCTest

/// The three controls that were drawn, tappable, and did nothing: the Subs tab's
/// magnifier, Home's Calendar, and the detail screen's overflow ellipsis.
///
/// Each was declared as a closure with a default value and never supplied, which
/// is the same defect v29 found across the whole write path — an interface that
/// looks complete and changes nothing. So each test asserts the destination
/// arrives, which is exactly what fails when the closure goes back to its default.
@MainActor
final class InertControlsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Search

    func testSearchFiltersToOneSubscriptionAndOpensIt() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-subs"]
        app.launch()

        let magnifier = app.buttons["magnifyingglass"].firstMatch
        XCTAssertTrue(magnifier.waitForExistence(timeout: 15), "the Subs tab must offer search")
        magnifier.tap()

        let field = app.textFields["Search subscriptions"]
        XCTAssertTrue(field.waitForExistence(timeout: 10),
                      "the magnifier opened nothing — the action is not wired")
        field.typeText("netfl")

        // Filtering is the claim, so the assertion is that a NON-match is gone.
        let match = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Netflix")
        ).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5), "the query must keep its match")
        // `exists`, not `isHittable`, would pass with the bug: the Subs tab is
        // still in the hierarchy underneath the cover, so its rows exist while
        // being unreachable.
        XCTAssertFalse(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Spotify")
        ).firstMatch.isHittable, "the query must exclude everything else")

        match.tap()
        XCTAssertTrue(app.buttons["Mark cancelled"].waitForExistence(timeout: 10),
                      "a search result must open the subscription")
    }

    // MARK: - Calendar

    func testCalendarShowsTheMonthAndOpensASubscription() {
        let app = XCUIApplication()
        app.launch()

        let calendar = app.buttons["Calendar"].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 15), "Home must offer Calendar")
        calendar.tap()

        XCTAssertTrue(app.staticTexts["Renewals"].waitForExistence(timeout: 10),
                      "Calendar opened nothing — the action is not wired")

        // The fixtures pin today to Jul 13 2026, so the month label is fixed too.
        XCTAssertTrue(app.staticTexts["July 2026"].exists, "the calendar must open on today's month")

        // Paging is real navigation, not decoration.
        app.buttons["Next month"].tap()
        XCTAssertTrue(app.staticTexts["August 2026"].waitForExistence(timeout: 5),
                      "the month stepper did not move")
        app.buttons["Previous month"].tap()
        XCTAssertTrue(app.staticTexts["July 2026"].waitForExistence(timeout: 5))

        // A renewal row reaches its subscription, so the calendar is a way in and
        // not just a picture.
        //
        // The hittable one, not the first: Home is still in the hierarchy under
        // the cover and its own Spotify row matches the same predicate. This is
        // the same trap the search test hit from the other side.
        let candidates = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Spotify"))
        XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: 5), "July must list its renewals")
        var row = candidates.allElementsBoundByIndex.first { $0.isHittable }
        // The list sits under the grid, so it can start below the fold.
        var scrolls = 0
        while row == nil, scrolls < 4 {
            app.swipeUp()
            scrolls += 1
            row = candidates.allElementsBoundByIndex.first { $0.isHittable }
        }
        XCTAssertNotNil(row, "the calendar's own Spotify row must be reachable")
        row?.tap()
        XCTAssertTrue(app.buttons["Mark cancelled"].waitForExistence(timeout: 10),
                      "a calendar row must open the subscription")
    }

    // MARK: - Rename and category

    func testRenamingASubscriptionShowsTheNewNameEverywhere() {
        let app = XCUIApplication()
        app.launch()

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Spotify")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()

        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "the detail screen must offer the overflow menu")
        more.tap()

        let rename = app.buttons["Rename…"]
        XCTAssertTrue(rename.waitForExistence(timeout: 10),
                      "the ellipsis opened nothing — the menu is not there")
        rename.tap()

        // The field's placeholder is the ENGINE's name, and it starts empty, so
        // typing is all it takes.
        let field = app.textFields["Spotify"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the rename sheet must offer a field")
        field.tap()
        field.typeText("Music (mine)")
        app.buttons["Save name"].tap()

        // Back to Home, which re-reads: the nickname is the display name now.
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Music (mine)")
        ).firstMatch.waitForExistence(timeout: 10),
        "the rename did not reach the provider")
    }

    func testChangingCategoryOffersTheUsersOwnCategories() {
        let app = XCUIApplication()
        app.launch()

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Spotify")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()

        app.buttons["More"].tap()
        let category = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "category")
        ).firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 10), "the menu must offer the category action")
        category.tap()

        XCTAssertTrue(app.staticTexts["Category"].waitForExistence(timeout: 10),
                      "the category sheet did not open")
        // Seeded by detection, offered by the client — never a taxonomy invented
        // here. The fixtures ship these, so their presence proves the list comes
        // from the user's own data.
        XCTAssertTrue(app.buttons["Shopping"].exists || app.buttons["AI"].exists,
                      "the sheet must offer the categories already in the data")
    }
}
