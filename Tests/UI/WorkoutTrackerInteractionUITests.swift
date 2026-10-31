import XCTest

final class WorkoutTrackerInteractionUITests: XCTestCase {
    /// Going to the background flips the appearance for the app switcher's snapshot, which must
    /// not rebuild the card and drop what the athlete dialled.
    @MainActor
    func testADialledWeightOutlastsTheAppGoingToTheBackground() throws {
        let app = launchFixtureApp()
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].appears(within: 3))
        for _ in 0..<2 {
            app.buttons["weight-increment"].tap()
        }
        waitForLabel("Weight, 247.5", on: app.buttons["weight-pill"])

        XCUIDevice.shared.press(.home)
        // A slow runner can suspend the app before a wait for .runningBackground first looks.
        let backgrounded = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.state != .runningForeground },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [backgrounded], timeout: 10), .completed, "still \(app.state)")
        app.activate()

        XCTAssertTrue(app.staticTexts["Set 1 of 3"].appears(within: 3))
        waitForLabel("Weight, 247.5", on: app.buttons["weight-pill"])
    }

    @MainActor
    func testDeveloperToolsRouteLoadsFromSettings() throws {
        let app = launchSettingsFixtureApp(options: [.pendingWrite])

        let trainingSheetRow = app.buttons["settings-training-sheet-row"]
        let syncNowButton = app.buttons["settings-sync-now-button"]
        let developerToolsRow = app.buttons["settings-developer-tools-row"]
        let signOutButton = app.buttons["settings-sign-out-button"]
        XCTAssertTrue(trainingSheetRow.exists)
        XCTAssertTrue(syncNowButton.exists)
        XCTAssertTrue(developerToolsRow.exists)
        XCTAssertTrue(signOutButton.exists)

        developerToolsRow.tap()
        XCTAssertTrue(app.navigationBars["Developer Tools"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Current Session Debug Info"].exists)
        XCTAssertTrue(app.staticTexts["Pending Sheet Writes"].exists)
        XCTAssertTrue(app.staticTexts["Actions"].exists)
        XCTAssertTrue(app.buttons["developer-tools-force-celebration-button"].exists)
        XCTAssertTrue(app.buttons["developer-tools-sync-button"].exists)

        app.navigationBars["Developer Tools"].buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 3))
    }

    @MainActor
    func testBlockOverviewSettingsRowOpensSettingsFromTheStage() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        app.buttons["session-location-button"].tap()
        XCTAssertTrue(app.navigationBars["Block 27"].appears(within: 3))

        tapWhenHittable(app.buttons["block-overview-settings-row"])
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 3))

        app.buttons["settings-done-button"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 3))
        XCTAssertTrue(app.navigationBars["Block 27"].exists)
    }

    @MainActor
    func testCompletionStageListsOpenExercisesAndNavigatesToSource() throws {
        let app = launchWorkoutApp(fixture: .completedSessionWithOpenExercises)

        XCTAssertTrue(app.staticTexts["Session complete"].appears(within: 3))

        let openBackSquat = app.buttons.containing(.staticText, identifier: "Back Squat").firstMatch
        XCTAssertTrue(openBackSquat.appears(within: 3))
        XCTAssertTrue(app.buttons["move-on-button"].exists)

        tapWhenHittable(openBackSquat)

        XCTAssertTrue(app.buttons["go-back-current-session-button"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Back Squat"].exists)
    }

    @MainActor
    func testTappingLastPerformedOpensExerciseHistorySheet() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        let lastPerformed = app.buttons["Block 26 · W4 D3 — 245x5@6, 255x5@7"]
        XCTAssertTrue(lastPerformed.appears(within: 3))
        tapWhenHittable(lastPerformed)

        XCTAssertTrue(app.staticTexts["Exercise History · last 5"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Block 26"].exists)
        XCTAssertTrue(app.staticTexts["Block 25"].exists)
        XCTAssertTrue(app.staticTexts["235×5"].exists)
    }

    /// A switch that would discard pending Set Logs waits on the confirmation card. A swipe on the
    /// picker under it once closed both and left the selection pending, so reopening the picker
    /// showed the card again with nothing chosen, one tap from discarding the Set Logs.
    @MainActor
    func testSwipingThePickerUnderASwitchConfirmationLeavesNoSwitchPending() throws {
        let app = launchSettingsFixtureApp(options: [.pendingWrite])

        let trainingSheetRow = app.buttons["settings-training-sheet-row"]
        tapWhenHittable(trainingSheetRow)
        let replacementRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Replacement Training Log")
        ).firstMatch
        tapWhenHittable(replacementRow)
        let confirmSwitch = app.buttons["switch-sheet-confirm-button"]
        XCTAssertTrue(confirmSwitch.appears(within: 3))

        // A drag that starts on an element under the card makes XCTest's interruption handler tap
        // the card's Cancel first, so the drag starts from a screen coordinate.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)),
            withVelocity: .fast,
            thenHoldForDuration: 0
        )
        XCTAssertFalse(confirmSwitch.waitForNonExistence(timeout: 2), "the swipe closed the picker under the card")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(confirmSwitch.disappears(within: 2))
        tapWhenHittable(app.buttons["sheet-picker-done-button"])
        XCTAssertTrue(app.buttons["sheet-picker-done-button"].disappears(within: 3))
        XCTAssertTrue(trainingSheetRow.label.contains("Fixture Training Log"))

        tapWhenHittable(trainingSheetRow)
        XCTAssertTrue(replacementRow.appears(within: 3))
        XCTAssertFalse(confirmSwitch.appears(within: 1), "reopening the picker brought back a pending switch")
    }

    @MainActor
    private func launchFixtureApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .currentSession)
    }

    @MainActor
    private func launchSettingsFixtureApp(options: [WorkoutUITestFixtureOption] = []) -> XCUIApplication {
        launchWorkoutApp(fixture: .settings, options: options)
    }
}
