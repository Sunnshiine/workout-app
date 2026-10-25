import XCTest

final class WorkoutTrackerSupersetUITests: XCTestCase {
    @MainActor
    func testQueuePairingCanBeCancelled() throws {
        let app = launchWorkoutApp(fixture: .currentSession)

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        app.buttons["stage-queue-button"].tap()
        XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))
        XCTAssertFalse(app.buttons["stage-queue-cancel-pairing"].exists)

        tapWhenHittable(app.buttons["stage-queue-superset"])
        XCTAssertTrue(app.buttons["stage-queue-cancel-pairing"].appears(within: 3))
        XCTAssertFalse(app.buttons["stage-queue-superset"].exists)

        tapWhenHittable(app.buttons["stage-queue-cancel-pairing"])

        XCTAssertTrue(app.buttons["stage-queue-superset"].appears(within: 3))
        XCTAssertFalse(app.buttons["stage-queue-cancel-pairing"].exists)
        XCTAssertFalse(app.buttons["stage-queue-row-superset-0"].exists)
    }

    @MainActor
    func testUnlinkInTheQueueSplitsTheSupersetBackIntoItsExercises() throws {
        let app = launchWorkoutApp(fixture: .currentSession)

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        app.buttons["stage-queue-button"].tap()
        XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))
        tapWhenHittable(app.buttons["stage-queue-superset"])
        tapWhenHittable(app.buttons["stage-queue-row-exercise-1"])
        XCTAssertTrue(app.staticTexts["This Session"].waitForNonExistence(timeout: 3))
        app.buttons["stage-queue-button"].tap()
        XCTAssertTrue(app.buttons["stage-queue-row-superset-0"].appears(within: 3))

        tapWhenHittable(app.buttons["stage-queue-unlink-superset-0"])

        XCTAssertTrue(app.buttons["stage-queue-row-exercise-0"].appears(within: 3))
        XCTAssertTrue(app.buttons["stage-queue-row-exercise-1"].exists)
        XCTAssertTrue(app.buttons["stage-queue-row-superset-0"].waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testPairingClosesTheQueueSoMoveOnCannotBeTappedByAccident() throws {
        let app = launchWorkoutApp(fixture: .currentSession)

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        app.buttons["stage-queue-button"].tap()
        XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))
        tapWhenHittable(app.buttons["stage-queue-superset"])
        tapWhenHittable(app.buttons["stage-queue-row-exercise-1"])

        XCTAssertTrue(app.staticTexts["This Session"].waitForNonExistence(timeout: 3))
        waitForLabel("& BB RDL", on: app.buttons["superset-partner-name"])
        XCTAssertFalse(app.buttons["queue-move-on-button"].exists)
    }
}
