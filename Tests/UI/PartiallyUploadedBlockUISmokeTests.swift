import XCTest

final class PartiallyUploadedBlockUISmokeTests: XCTestCase {
    @MainActor
    func testUnavailableSessionIsInertAndAvailableSessionOpens() throws {
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
    private func launchPartialBlockOverviewApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .partiallyUploadedBlock)
    }
}
