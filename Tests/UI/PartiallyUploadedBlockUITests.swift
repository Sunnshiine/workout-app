import XCTest

final class PartiallyUploadedBlockUITests: XCTestCase {
    @MainActor
    func testTerminalMoveOnReturnsToAccessibleBlockGrid() throws {
        let app = launchPartialBlockOverviewApp()

        XCTAssertTrue(app.navigationBars["Block 27"].appears(within: 3))
        app.otherElements["session-tile-W4-D1"].tap()
        waitForLabel("Open Block Overview for Week 4, Day 1", on: app.buttons["session-location-button"])
        XCTAssertEqual(app.staticTexts["stage-exercise-name"].label, "Accessory")

        app.buttons["make-current-session-button"].tap()
        let queueButton = app.buttons["stage-queue-button"]
        XCTAssertTrue(queueButton.appears(within: 3))
        queueButton.tap()
        tapWhenHittable(app.buttons["queue-move-on-button"])

        let celebration = app.otherElements["move-on-celebration"]
        XCTAssertTrue(celebration.appears(within: 3))
        XCTAssertEqual(celebration.label, "Week 4, Day 1")
        waitForValueContaining("1 Sets, 1 Exercises, 1 Left", on: celebration)

        app.buttons["move-on-celebration-continue"].tap()

        XCTAssertTrue(app.navigationBars["Block 27"].appears(within: 3))
        XCTAssertFalse(celebration.exists)
        XCTAssertTrue(app.otherElements["session-tile-W4-D1"].appears(within: 3))
        XCTAssertTrue(app.otherElements["session-tile-W4-D2"].exists)
    }

    @MainActor
    private func launchPartialBlockOverviewApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .partiallyUploadedBlock)
    }
}
