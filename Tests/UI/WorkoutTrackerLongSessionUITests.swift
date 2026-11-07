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
        assertRests(onStage, onTheWheelsCentreIn: app)

        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: onStage.frame.midX, dy: center))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stage-queue-row-'"))
        for distance in [-100, -37, 43.0] {
            start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)))
            waitForFrameToSettle(of: onStage)

            XCTAssertTrue(app.staticTexts["This Session"].exists, "a drag over a row does not jump to it")
            let nearest = rows.allElementsBoundByIndex.map { abs($0.frame.midY - center) }.min() ?? .infinity
            XCTAssertLessThan(nearest, 2, "a row rests on the wheel's centre after a \(distance)pt drag")
        }
        XCTAssertNotEqual(onStage.frame.midY, center, accuracy: 1, "the wheel moved")
    }

    @MainActor
    func testAtTheLargestScaledTextTheWheelOpensOnTheExerciseOnStage() throws {
        let app = launchWorkoutApp(fixture: .longSession, contentSize: "UICTContentSizeCategoryXXXL")
        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        app.buttons["stage-queue-button"].tap()
        let onStage = app.buttons["stage-queue-row-exercise-1"]
        XCTAssertTrue(onStage.appears(within: 3))
        waitForFrameToSettle(of: onStage)

        assertRests(onStage, onTheWheelsCentreIn: app)
    }

    /// The wheel fills the space between the header's button and Move On.
    @MainActor
    private func assertRests(_ row: XCUIElement, onTheWheelsCentreIn app: XCUIApplication) {
        let top = app.buttons["stage-queue-superset"].frame.maxY
        let bottom = app.buttons["queue-move-on-button"].frame.minY
        XCTAssertEqual(row.frame.midY, (top + bottom) / 2, accuracy: 3, "the row on stage rests on the wheel's centre")
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
