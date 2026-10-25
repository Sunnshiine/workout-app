import XCTest

final class WorkoutTrackerLongSessionUITests: XCTestCase {
    @MainActor
    func testAFinishedExercisesRowReopensItWithItsLoggedSetUnderReview() throws {
        let app = launchFixtureApp()
        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        app.buttons["stage-queue-button"].tap()
        XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))
        app.buttons["stage-queue-row-exercise-0"].tap()

        XCTAssertTrue(app.staticTexts["Set 1 of 1"].appears(within: 3))
        XCTAssertEqual(app.staticTexts["stage-exercise-name"].label, "Primer Row")
        XCTAssertEqual(app.descendants(matching: .any)["logged-set-capsule"].label, "95x8@6", "its logged Set is open for review")
    }

    @MainActor
    func testLongSessionQueueListsEveryExerciseAndJumpLandsOnStage() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        let queueButton = app.buttons["stage-queue-button"]
        waitForValue("2 of 8", on: queueButton)
        queueButton.tap()

        XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))
        XCTAssertTrue(app.buttons["stage-queue-row-exercise-0"].isEnabled, "a finished Exercise stays reachable")

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
