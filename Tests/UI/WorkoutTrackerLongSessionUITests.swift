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
            app.buttons["stage-queue-row-exercise-0"].swipeUp()
        }
        tapWhenHittable(farmerCarryRow)

        XCTAssertTrue(app.staticTexts["Farmer Carry"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Tall posture."].exists)
    }

    @MainActor
    func testDraggingTheWheelOverARowScrollsItAndRestsARowOnTheCentre() throws {
        let app = launchFixtureApp()
        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        app.buttons["stage-queue-button"].tap()
        XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))
        let onStage = app.buttons["stage-queue-row-exercise-1"]
        XCTAssertTrue(onStage.appears(within: 3))
        waitForFrameToSettle(of: onStage)
        let center = onStage.frame.midY

        let below = app.buttons["stage-queue-row-exercise-2"]
        let start = below.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -100)))
        waitForFrameToSettle(of: onStage)

        XCTAssertTrue(app.staticTexts["This Session"].exists, "a drag over a row does not jump to it")
        XCTAssertNotEqual(onStage.frame.midY, center, accuracy: 1, "the wheel moved")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stage-queue-row-'")).allElementsBoundByIndex
        let nearest = rows.map { abs($0.frame.midY - center) }.min() ?? .infinity
        XCTAssertLessThan(nearest, 2, "a row rests on the wheel's centre")
    }

    /// The wheel coasts, then snaps. A frame unchanged across a quarter second has come to rest.
    @MainActor
    private func waitForFrameToSettle(of element: XCUIElement) {
        var last = element.frame.midY
        let deadline = Date().addingTimeInterval(5)
        repeat {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            let current = element.frame.midY
            if current == last { return }
            last = current
        } while Date() < deadline
    }

    @MainActor
    private func launchFixtureApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .longSession)
    }
}
