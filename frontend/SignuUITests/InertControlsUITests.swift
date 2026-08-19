import XCTest

@MainActor
final class InertControlsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }


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

        let match = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Netflix")
        ).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5), "the query must keep its match")
        XCTAssertFalse(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Spotify")
        ).firstMatch.isHittable, "the query must exclude everything else")

        match.tap()
        XCTAssertTrue(app.buttons["Mark cancelled"].waitForExistence(timeout: 10),
                      "a search result must open the subscription")
    }


    func testCalendarShowsTheMonthAndOpensASubscription() {
        let app = XCUIApplication()
        app.launch()

        let calendar = app.buttons["Calendar"].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 15), "Home must offer Calendar")
        calendar.tap()

        XCTAssertTrue(app.staticTexts["Renewals"].waitForExistence(timeout: 10),
                      "Calendar opened nothing — the action is not wired")

        XCTAssertTrue(app.staticTexts["July 2026"].exists, "the calendar must open on today's month")

        app.buttons["Next month"].tap()
        XCTAssertTrue(app.staticTexts["August 2026"].waitForExistence(timeout: 5),
                      "the month stepper did not move")
        app.buttons["Previous month"].tap()
        XCTAssertTrue(app.staticTexts["July 2026"].waitForExistence(timeout: 5))

        let candidates = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Spotify"))
        XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: 5), "July must list its renewals")
        var row = candidates.allElementsBoundByIndex.first { $0.isHittable }
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


    func testHomeOffersReviewWhenOnlySuggestionsExist() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-suggestions"]
        app.launch()

        XCTAssertTrue(app.staticTexts["No confirmed subscriptions yet"].waitForExistence(timeout: 15),
                      "the headline must distinguish found from confirmed")
        XCTAssertTrue(app.staticTexts["Possible subscriptions found"].exists,
                      "Home must say what was found")
        let subsTab = app.buttons["Subs"]
        XCTAssertTrue(subsTab.exists)
        XCTAssertEqual(subsTab.value as? String, "2 to review",
                       "the Subs tab must carry the count")

        let card = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Possible subscriptions found")
        ).firstMatch
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Track it"].firstMatch.waitForExistence(timeout: 10),
                      "the card must open the review screen")
    }

    func testDecidingOnEverySuggestionClearsTheDot() {
        let app = XCUIApplication()
        app.launchArguments = ["--shell-suggestions"]
        app.launch()

        let card = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Possible subscriptions found")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()

        for _ in 0..<2 {
            let dismiss = app.buttons["Not a subscription"].firstMatch
            XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
            dismiss.tap()
        }
        app.buttons["Back"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["No subscriptions detected yet"].waitForExistence(timeout: 10),
                      "with nothing left to review the headline goes back to the plain one")
        XCTAssertFalse(app.staticTexts["Possible subscriptions found"].exists,
                       "the card must go with the suggestions")
        let subsValue = app.buttons["Subs"].value as? String
        XCTAssertTrue(subsValue == nil || subsValue?.isEmpty == true,
                      "the dot must clear at zero, and its count with it")
    }


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

        let field = app.textFields["Spotify"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the rename sheet must offer a field")
        field.tap()
        field.typeText("Music (mine)")
        app.buttons["Save name"].tap()

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
        XCTAssertTrue(app.buttons["Shopping"].exists || app.buttons["AI"].exists,
                      "the sheet must offer the categories already in the data")
    }
}
