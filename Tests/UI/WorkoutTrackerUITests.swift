import XCTest

final class WorkoutTrackerInteractionUITests: XCTestCase {
    @MainActor
    func testActiveSetFieldFocusDismissesWithoutCardCancel() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)

        openWeightKeyboard(in: app)

        tapActiveSetCardHeaderBackground(in: app)

        XCTAssertFalse(app.keyboards.firstMatch.appears(within: 1))
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
    }

    @MainActor
    func testActiveSetLogButtonSubmitsOnFirstCenterTapWhileWeightFieldIsFocused() throws {
        let app = launchFixtureApp(options: [.offline])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 237.5 × 5 @6", on: logButton)

        openWeightKeyboard(in: app)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "230")
        waitForLabel("Log 230 × 5 @6", on: logButton)

        XCTAssertLessThanOrEqual(logButton.frame.maxY, try keyboardToolbarTop(in: app))
        let exerciseName = app.staticTexts["stage-exercise-name"]
        XCTAssertTrue(exerciseName.exists)
        XCTAssertEqual(exerciseName.label, "Back Squat")

        logButton.tap()

        XCTAssertTrue(app.buttons["Set 1, 230x5@6"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        openWeightKeyboard(in: app)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "240")
        waitForLabel("Log 240 × 5 @7", on: logButton)

        XCTAssertLessThanOrEqual(logButton.frame.maxY, try keyboardToolbarTop(in: app))

        logButton.tap()

        XCTAssertTrue(app.buttons["Set 2, 240x5@7"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 3 of 3"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        let restPill = app.descendants(matching: .any)["rest-pill"]
        XCTAssertTrue(restPill.exists)
        XCTAssertLessThanOrEqual(logButton.frame.maxY, restPill.frame.minY, "rest is back in the foot below the card")
    }

    @MainActor
    func testEveryWeightEditClosedWithDoneKeepsLogInReach() throws {
        let app = launchFixtureApp(options: [.offline], animated: true)

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        let card = app.otherElements["active-set-card"]
        let idleTop = settledFrame(of: card).minY
        var cardTops: [CGFloat] = []
        for _ in 1...3 {
            openWeightKeyboard(in: app)
            cardTops.append(settledFrame(of: card).minY)
            app.buttons["weight-keyboard-done"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        }
        XCTAssertEqual(cardTops[2], cardTops[0], accuracy: 1, "edit tops \(cardTops)")

        openWeightKeyboard(in: app)
        app.buttons["log-active-set-button"].tap()

        XCTAssertTrue(app.buttons["Set 1, 237.5x5@6"].appears(within: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(settledFrame(of: card).minY, idleTop, accuracy: 1, "a keyboard-up log leaves no keyboard inset")
    }

    @MainActor
    func testWeightKeyboardDoneKeepsTheSystemButtonFont() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        openWeightKeyboard(in: app)

        XCTAssertEqual(
            app.buttons["weight-keyboard-done"].frame.width,
            38,
            accuracy: 2,
            "at the default text size, the Done glyph in the system font measures 38"
        )
    }

    @MainActor
    func testSupersetLogButtonSubmitsOnFirstCenterTapWhileWeightFieldIsFocused() throws {
        let app = launchFixtureApp(options: [.offline])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        pairBackSquatWithBBRDL(in: app)

        let logButton = app.buttons["log-active-set-button"]
        openWeightKeyboard(in: app)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "230")
        waitForLabel("Log 230 × 5 @6", on: logButton)
        XCTAssertLessThanOrEqual(logButton.frame.maxY, try keyboardToolbarTop(in: app))

        logButton.tap()

        waitForLabel("BB RDL", on: app.staticTexts["stage-exercise-name"])
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    @MainActor
    func testSupersetNameShedWhileWeightFieldIsFocusedLeavesTheAccessibilityTree() throws {
        let app = launchFixtureApp(options: [.offline])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        pairBackSquatWithBBRDL(in: app)
        let logButton = app.buttons["log-active-set-button"]
        logButton.tap()
        waitForLabel("BB RDL", on: app.staticTexts["stage-exercise-name"])
        XCTAssertTrue(app.staticTexts["Sync status: 1 unsynced"].appears(within: 3))

        openWeightKeyboard(in: app)
        XCTAssertLessThanOrEqual(logButton.frame.maxY, try keyboardToolbarTop(in: app))

        XCTAssertFalse(app.staticTexts["stage-exercise-name"].exists, "BB RDL's name is not drawn")
        XCTAssertFalse(app.buttons["superset-partner-name"].exists, "the & Back Squat switch is not drawn")

        app.buttons["weight-keyboard-done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        let restPill = app.descendants(matching: .any)["rest-pill"]
        XCTAssertTrue(restPill.exists)
        XCTAssertLessThanOrEqual(logButton.frame.maxY, restPill.frame.minY, "rest is back in the foot below the card")
    }

    @MainActor
    func testTapOnNonInteractiveStageContentDismissesKeyboard() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let hud = app.otherElements["session-header-hud"]
        let stageTop = hud.frame.minY
        let weightControls = app.descendants(matching: .any).matching(identifier: "weight-pill")
        XCTAssertEqual(weightControls.count, 1)
        XCTAssertEqual(app.textFields.count, 0, "an idle weight exposes no text field")

        openWeightKeyboard(in: app)
        XCTAssertFalse(hud.exists, "the HUD steps aside while the weight is being edited")
        XCTAssertEqual(weightControls.count, 1)
        XCTAssertEqual(app.textFields.count, 1)

        tapEmptyStageSpaceAboveExerciseName(in: app, stageTop: stageTop)

        XCTAssertFalse(app.keyboards.firstMatch.appears(within: 1))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        waitForLabel("Weight, 237.5", on: app.buttons["weight-pill"])
        XCTAssertEqual(weightControls.count, 1)
        XCTAssertEqual(app.textFields.count, 0, "a folded weight exposes no text field")
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
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
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 3))
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

        let lastPerformed = app.staticTexts["Block 26 · W4 D3 — 245x5@6, 255x5@7"]
        XCTAssertTrue(lastPerformed.appears(within: 3))
        tapWhenHittable(lastPerformed)

        XCTAssertTrue(app.staticTexts["Exercise History · last 5"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Block 26"].exists)
        XCTAssertTrue(app.staticTexts["Block 25"].exists)
        XCTAssertTrue(app.staticTexts["235×5"].exists)
    }

    @MainActor
    func testSwipeDismissingASheetOpenedWhileTypingFoldsTheWeightEdit() throws {
        // With UIKit animations off, a closing sheet never hands its first responder back, so only
        // an animated launch takes the path an athlete takes (#697).
        let app = launchFixtureApp(animated: true)

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        openWeightKeyboard(in: app)
        XCTAssertFalse(app.otherElements["session-header-hud"].exists)

        tapWhenHittable(app.staticTexts["last-performed-line"])
        let historyTitle = app.staticTexts["Exercise History · last 5"]
        XCTAssertTrue(historyTitle.appears(within: 3))
        historyTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)),
            withVelocity: .fast,
            thenHoldForDuration: 0
        )
        XCTAssertTrue(historyTitle.waitForNonExistence(timeout: 3))

        XCTAssertFalse(app.keyboards.firstMatch.appears(within: 1), "closing the sheet reopened the weight keyboard")
        XCTAssertTrue(app.otherElements["session-header-hud"].exists)
        XCTAssertTrue(app.buttons["stage-queue-button"].exists)
        waitForLabel("Weight, 237.5", on: app.buttons["weight-pill"])
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "weight-pill").count, 1)
        XCTAssertEqual(app.textFields.count, 0, "a folded weight exposes no text field")
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
        XCTAssertTrue(confirmSwitch.waitForNonExistence(timeout: 2))
        tapWhenHittable(app.buttons["sheet-picker-done-button"])
        XCTAssertTrue(app.navigationBars["Training Sheet"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(trainingSheetRow.label.contains("Fixture Training Log"))

        tapWhenHittable(trainingSheetRow)
        XCTAssertTrue(replacementRow.appears(within: 3))
        XCTAssertFalse(confirmSwitch.appears(within: 1), "reopening the picker brought back a pending switch")
    }

    @MainActor
    private func launchFixtureApp(options: [WorkoutUITestFixtureOption] = [], animated: Bool = false) -> XCUIApplication {
        launchWorkoutApp(fixture: .currentSession, options: options, animated: animated)
    }

    @MainActor
    private func launchSettingsFixtureApp(options: [WorkoutUITestFixtureOption] = []) -> XCUIApplication {
        launchWorkoutApp(fixture: .settings, options: options)
    }
}

@MainActor
private func pairBackSquatWithBBRDL(in app: XCUIApplication) {
    app.buttons["stage-queue-button"].tap()
    XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))
    tapWhenHittable(app.buttons["stage-queue-superset"])
    tapWhenHittable(app.buttons["stage-queue-row-exercise-1"])
    tapWhenHittable(app.buttons["stage-queue-row-superset-0"])
    waitForLabel("& BB RDL", on: app.buttons["superset-partner-name"])
}

@MainActor
private func tapEmptyStageSpaceAboveExerciseName(in app: XCUIApplication, stageTop: CGFloat) {
    let nameTop = app.staticTexts["stage-exercise-name"].frame.minY
    app.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: app.frame.midX, dy: (stageTop + nameTop) / 2))
        .tap()
}

@MainActor
private func openWeightKeyboard(in app: XCUIApplication) {
    app.buttons["weight-pill"].tap()
    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.appears(within: 3))
    let deadline = Date().addingTimeInterval(3)
    while keyboard.frame.minY >= app.frame.maxY, Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTAssertLessThan(
        keyboard.frame.minY,
        app.frame.maxY,
        "the software keyboard is below the window. scripts/test-sim.sh fixes the simulator's keyboard "
            + "preference before UI runs; for another runner, run scripts/sim-keyboard.sh ensure <udid> (#700)"
    )
}

@MainActor
private func settledFrame(of element: XCUIElement) -> CGRect {
    var frame = element.frame
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let next = element.frame
        if next == frame { return frame }
        frame = next
    }
    XCTFail("\(element) still moving after 3 s, last at \(frame)")
    return frame
}

/// The keyboard's Done toolbar is the `Toolbar` group that is not the full-window one.
@MainActor
private func keyboardToolbarTop(in app: XCUIApplication) throws -> CGFloat {
    let toolbars = app.descendants(matching: .any).matching(identifier: "Toolbar").allElementsBoundByIndex
    return try XCTUnwrap(toolbars.first { $0.frame.height < app.frame.height }).frame.minY
}

@MainActor
private func tapActiveSetCardHeaderBackground(in app: XCUIApplication) {
    let activeSetCard = app.otherElements["active-set-card"]
    XCTAssertTrue(activeSetCard.appears(within: 3))
    activeSetCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14)).tap()
}
