import XCTest

final class PartiallyUploadedBlockUISmokeTests: XCTestCase {
    @MainActor
    func testUnavailableSessionIsInertAndAvailableSessionOpens() throws {
        let app = launchPartialBlockOverviewApp()

        XCTAssertTrue(app.navigationBars["Block 27"].appears(within: 3))
        let unavailableTile = app.otherElements["session-tile-W1-D3"]
        XCTAssertTrue(unavailableTile.appears(within: 3))
        waitForValue("Not uploaded", on: unavailableTile)
        XCTAssertFalse(unavailableTile.buttons.firstMatch.exists)
        XCTAssertTrue(app.otherElements["session-tile-W1-D2"].buttons.firstMatch.exists)

        unavailableTile.tap()

        XCTAssertTrue(app.navigationBars["Block 27"].exists)
        XCTAssertFalse(app.staticTexts["Bench Press"].exists)

        app.otherElements["session-tile-W1-D2"].tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].appears(within: 3))
    }

    @MainActor
    private func launchPartialBlockOverviewApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .partiallyUploadedBlock)
    }
}
