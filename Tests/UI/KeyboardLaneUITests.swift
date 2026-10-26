import XCTest

/// The weight keyboard tests, which CI runs on every pull request that touches the session views.
/// Each one launches animated, because with animations off the active-set card rests 34 pt higher
/// than an athlete sees it and a closing sheet never hands its first responder back (#697).
final class KeyboardLaneUITests: XCTestCase {
    @MainActor
    func testLogStaysClearOfTheKeyboardWhileItRises() throws {
        let app = launchAnimated(options: [.offline])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        let logButton = app.buttons["log-active-set-button"]
        for edit in 1...3 {
            centreTap(app.buttons["weight-pill"])
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : .infinity
                let logBottom = logButton.frame.maxY
                if logBottom > keyboardTop + 1 {
                    XCTFail("edit \(edit): Log maxY \(logBottom) under the rising keyboard at \(keyboardTop)")
                }
            }
            waitForKeyboardOnScreen(in: app)
            XCTAssertLessThanOrEqual(settledFrame(of: logButton).maxY, keyboardCoverTop(in: app), "edit \(edit)")
            centreTap(app.buttons["weight-keyboard-done"])
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        }

        openWeightKeyboard(in: app)
        XCTAssertLessThanOrEqual(settledFrame(of: logButton).maxY, keyboardCoverTop(in: app))
        centreTap(logButton)
        XCTAssertTrue(app.buttons["Set 1, 237.5x5@6"].appears(within: 3), "a centred Log tap with the keyboard up logs")
    }

    @MainActor
    func testActiveSetFieldFocusDismissesWithoutCardCancel() throws {
        let app = launchAnimated(options: [])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)

        openWeightKeyboard(in: app)

        tapActiveSetCardHeaderBackground(in: app)

        assertKeyboardFoldsAndStaysDown(in: app)
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
    }

    @MainActor
    func testActiveSetLogButtonSubmitsOnFirstCenterTapWhileWeightFieldIsFocused() throws {
        let app = launchAnimated(options: [.offline])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 237.5 × 5 @6", on: logButton)

        openWeightKeyboard(in: app)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "230")
        waitForLabel("Log 230 × 5 @6", on: logButton)

        XCTAssertLessThanOrEqual(settledFrame(of: logButton).maxY, keyboardCoverTop(in: app))
        let exerciseName = app.staticTexts["stage-exercise-name"]
        XCTAssertTrue(exerciseName.exists)
        XCTAssertEqual(exerciseName.label, "Back Squat")

        logButton.tap()

        XCTAssertTrue(app.buttons["Set 1, 230x5@6"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))

        openWeightKeyboard(in: app)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "240")
        waitForLabel("Log 240 × 5 @7", on: logButton)

        XCTAssertLessThanOrEqual(settledFrame(of: logButton).maxY, keyboardCoverTop(in: app))

        logButton.tap()

        XCTAssertTrue(app.buttons["Set 2, 240x5@7"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 3 of 3"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        assertLogSitsAboveTheRestPill(in: app)
    }

    @MainActor
    func testEveryWeightEditClosedWithDoneKeepsLogInReach() throws {
        let app = launchAnimated(options: [.offline])

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
        let app = launchAnimated(options: [])

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
        let app = launchAnimated(options: [.offline])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        pairBackSquatWithBBRDL(in: app)

        let logButton = app.buttons["log-active-set-button"]
        openWeightKeyboard(in: app)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "230")
        waitForLabel("Log 230 × 5 @6", on: logButton)
        XCTAssertLessThanOrEqual(settledFrame(of: logButton).maxY, keyboardCoverTop(in: app))

        logButton.tap()

        waitForLabel("BB RDL", on: app.staticTexts["stage-exercise-name"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testSupersetNameShedWhileWeightFieldIsFocusedLeavesTheAccessibilityTree() throws {
        let app = launchAnimated(options: [.offline])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        pairBackSquatWithBBRDL(in: app)
        let logButton = app.buttons["log-active-set-button"]
        logButton.tap()
        waitForLabel("BB RDL", on: app.staticTexts["stage-exercise-name"])
        XCTAssertTrue(app.staticTexts["Sync status: 1 unsynced"].appears(within: 3))

        openWeightKeyboard(in: app)
        XCTAssertLessThanOrEqual(settledFrame(of: logButton).maxY, keyboardCoverTop(in: app))

        XCTAssertFalse(app.staticTexts["stage-exercise-name"].exists, "BB RDL's name is not drawn")
        XCTAssertFalse(app.buttons["superset-partner-name"].exists, "the & Back Squat switch is not drawn")

        app.buttons["weight-keyboard-done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        assertLogSitsAboveTheRestPill(in: app)
    }

    @MainActor
    func testTapOnNonInteractiveStageContentDismissesKeyboard() throws {
        let app = launchAnimated(options: [])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let hud = app.otherElements["session-header-hud"]
        let stageTop = settledFrame(of: hud).minY
        let weightControls = app.descendants(matching: .any).matching(identifier: "weight-pill")
        XCTAssertEqual(weightControls.count, 1)
        XCTAssertEqual(app.textFields.count, 0, "an idle weight exposes no text field")

        openWeightKeyboard(in: app)
        XCTAssertFalse(hud.exists, "the HUD steps aside while the weight is being edited")
        XCTAssertEqual(weightControls.count, 1)
        XCTAssertEqual(app.textFields.count, 1)

        tapEmptyStageSpaceAboveExerciseName(in: app, stageTop: stageTop)

        assertKeyboardFoldsAndStaysDown(in: app)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        waitForLabel("Weight, 237.5", on: app.buttons["weight-pill"])
        XCTAssertEqual(weightControls.count, 1)
        XCTAssertEqual(app.textFields.count, 0, "a folded weight exposes no text field")
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
    }

    @MainActor
    func testSwipeDismissingASheetOpenedWhileTypingFoldsTheWeightEdit() throws {
        let app = launchAnimated(options: [])

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

    @MainActor
    private func launchAnimated(options: [WorkoutUITestFixtureOption]) -> XCUIApplication {
        launchWorkoutApp(fixture: .currentSession, options: options, animated: true)
    }
}

@MainActor
private func pairBackSquatWithBBRDL(in app: XCUIApplication) {
    app.buttons["stage-queue-button"].tap()
    XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))
    tapWhenHittable(app.buttons["stage-queue-superset"])
    tapWhenHittable(app.buttons["stage-queue-row-exercise-1"])
    waitForLabel("& BB RDL", on: app.buttons["superset-partner-name"])
}

@MainActor
private func tapEmptyStageSpaceAboveExerciseName(in app: XCUIApplication, stageTop: CGFloat) {
    let nameTop = settledFrame(of: app.staticTexts["stage-exercise-name"]).minY
    app.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: app.frame.midX, dy: (stageTop + nameTop) / 2))
        .tap()
}

@MainActor
private func centreTap(_ element: XCUIElement) {
    XCTAssertTrue(element.appears(within: 3), "\(element) missing")
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
}

/// Opens the weight keyboard and returns once the active-set card has stopped moving.
@MainActor
private func openWeightKeyboard(in app: XCUIApplication) {
    app.buttons["weight-pill"].tap()
    waitForKeyboardOnScreen(in: app)
    _ = settledFrame(of: app.otherElements["active-set-card"])
}

@MainActor
private func waitForKeyboardOnScreen(in app: XCUIApplication) {
    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(
        keyboard.appears(within: 3),
        "no software keyboard: keyboards \(app.keyboards.count), Done at \(app.buttons["weight-keyboard-done"].frame), "
            + "window \(app.frame)"
    )
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

/// Animated, the keyboard is still sliding out when the dismissing tap returns, so a bare `exists`
/// check finds it.
@MainActor
private func assertKeyboardFoldsAndStaysDown(in app: XCUIApplication) {
    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3), "the keyboard is still up")
    XCTAssertFalse(keyboard.appears(within: 1), "the keyboard came back up")
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

/// The keys and the Done glass button over the keyboard's toolbar row hide what sits below this
/// line. The row itself draws nothing. At the animated rest Log ends 5 pt below Done's top edge,
/// beside it, and stays in reach.
@MainActor
private func keyboardCoverTop(in app: XCUIApplication) -> CGFloat {
    min(app.keyboards.firstMatch.frame.minY, app.buttons["weight-keyboard-done"].frame.midY)
}

@MainActor
private func assertLogSitsAboveTheRestPill(in app: XCUIApplication) {
    let restPill = app.descendants(matching: .any)["rest-pill"]
    XCTAssertTrue(restPill.exists)
    XCTAssertLessThanOrEqual(
        settledFrame(of: app.buttons["log-active-set-button"]).maxY,
        settledFrame(of: restPill).minY,
        "rest is back in the foot below the card"
    )
}

@MainActor
private func tapActiveSetCardHeaderBackground(in app: XCUIApplication) {
    let activeSetCard = app.otherElements["active-set-card"]
    XCTAssertTrue(activeSetCard.appears(within: 3))
    activeSetCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14)).tap()
}
