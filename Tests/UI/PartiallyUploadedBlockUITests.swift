import XCTest

final class PartiallyUploadedBlockUITests: XCTestCase {
    @MainActor
    func testTerminalMoveOnReturnsToAccessibleBlockGrid() throws {
        let app = launchPartialBlockOverviewApp()

        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 5))
        tapElement(withIdentifier: "session-tile-W4-D1", in: app)
        XCTAssertTrue(app.staticTexts["Accessory W4 D1"].waitForExistence(timeout: 3))

        app.buttons["make-current-session-button"].tap()
        let queueButton = app.buttons["stage-queue-button"]
        XCTAssertTrue(queueButton.waitForExistence(timeout: 3))
        queueButton.tap()
        tapWhenHittable(app.buttons["queue-move-on-button"])

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
