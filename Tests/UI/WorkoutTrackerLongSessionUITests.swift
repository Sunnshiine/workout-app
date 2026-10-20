import XCTest

final class WorkoutTrackerLongSessionUITests: XCTestCase {
    @MainActor
    func testLongSessionQueueListsEveryExerciseAndJumpLandsOnStage() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        let queueButton = app.buttons["stage-queue-button"]
        waitForValue("2 of 8", on: queueButton)
        queueButton.tap()

        XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))
        XCTAssertFalse(app.buttons["stage-queue-row-exercise-0"].isEnabled)

        let farmerCarryRow = app.buttons["stage-queue-row-exercise-7"]
        XCTAssertTrue(farmerCarryRow.exists)
        if !farmerCarryRow.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
                .press(
                    forDuration: 0.1,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                )
        }
        tapWhenHittable(farmerCarryRow)

        XCTAssertTrue(app.staticTexts["Farmer Carry"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Tall posture."].exists)
    }

    @MainActor
    private func launchFixtureApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .longSession)
    }
}
