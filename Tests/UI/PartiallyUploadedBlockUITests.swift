import XCTest

final class PartiallyUploadedBlockUITests: XCTestCase {
    @MainActor
    func testPartiallyUploadedBlockGridShowsUnavailableTilesAsInert() throws {
        let app = launchPartialBlockOverviewApp()

        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 5))
        let unavailableTile = app.descendants(matching: .any)["session-tile-W1-D3"]
        XCTAssertTrue(unavailableTile.waitForExistence(timeout: 3))
        waitForValue("Not uploaded", on: unavailableTile)
        XCTAssertFalse(app.buttons["Week 1, Day 3"].exists)

        unavailableTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.navigationBars["Block 27"].exists)
        XCTAssertFalse(app.staticTexts["Bench Press"].exists)

        app.buttons["Week 1, Day 2"].tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTerminalMoveOnReturnsToAccessibleBlockGrid() throws {
        let app = launchPartialBlockOverviewApp()

        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 5))
        tapElement(withIdentifier: "session-tile-W4-D1", in: app)
        XCTAssertTrue(app.staticTexts["Accessory W4 D1"].waitForExistence(timeout: 3))

        app.buttons["make-current-session-button"].tap()
        XCTAssertTrue(app.buttons["move-on-button"].waitForExistence(timeout: 3))
        app.buttons["move-on-button"].tap()

        let celebration = moveOnCelebration(in: app)
        XCTAssertTrue(celebration.waitForExistence(timeout: 3))
        XCTAssertEqual(celebration.label, "Week 4, Day 1")
        waitForValueContaining("1 Sets, 1 Exercises, 1 Left", on: celebration)

        celebration.tap()

        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 3))
        XCTAssertFalse(celebration.exists)
        XCTAssertTrue(app.descendants(matching: .any)["session-tile-W4-D1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["session-tile-W4-D2"].exists)
    }

    @MainActor
    private func launchPartialBlockOverviewApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .partiallyUploadedBlock)
    }

    @MainActor
    private func tapElement(withIdentifier identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        element.tap()
    }
}
