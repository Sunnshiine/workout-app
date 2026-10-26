import XCTest

/// The weight keyboard tests, which CI runs on every pull request that touches the session views.
/// Each one launches animated, because with animations off the active-set card rests 34 pt higher
/// than an athlete sees it and a closing sheet never hands its first responder back (#697).
final class KeyboardLaneUITests: XCTestCase {
    @MainActor
    func testLogStaysClearOfTheKeyboardOnEveryEditAndLogsOnACentredTap() throws {
        let app = launchAnimated(options: [.offline])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: uiEventBudget))
        let logButton = app.buttons["log-active-set-button"]
        for edit in 1...3 {
            centreTap(app.buttons["weight-pill"])
            waitForKeyboardOnScreen(in: app)
            XCTAssertLessThanOrEqual(restingFrame(of: logButton, keyboard: .up, in: app).maxY, keyboardCoverTop(in: app), "edit \(edit)")
            centreTap(app.buttons["weight-keyboard-done"])
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: uiEventBudget))
        }

        openWeightKeyboard(in: app)
        XCTAssertLessThanOrEqual(restingFrame(of: logButton, keyboard: .up, in: app).maxY, keyboardCoverTop(in: app))
        centreTap(logButton)
        XCTAssertTrue(app.buttons["Set 1, 237.5x5@6"].appears(within: uiEventBudget), "a centred Log tap with the keyboard up logs")
    }

    @MainActor
    func testActiveSetFieldFocusDismissesWithoutCardCancel() throws {
        let app = launchAnimated(options: [])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: uiEventBudget))
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

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: uiEventBudget))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 237.5 × 5 @6", on: logButton)

        openWeightKeyboard(in: app)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "230")
        waitForLabel("Log 230 × 5 @6", on: logButton)

        XCTAssertLessThanOrEqual(restingFrame(of: logButton, keyboard: .up, in: app).maxY, keyboardCoverTop(in: app))
        let exerciseName = app.staticTexts["stage-exercise-name"]
        XCTAssertTrue(exerciseName.exists)
        XCTAssertEqual(exerciseName.label, "Back Squat")

        logButton.tap()

        XCTAssertTrue(app.buttons["Set 1, 230x5@6"].appears(within: uiEventBudget))
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: uiEventBudget))

        openWeightKeyboard(in: app)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "240")
        waitForLabel("Log 240 × 5 @7", on: logButton)

        XCTAssertLessThanOrEqual(restingFrame(of: logButton, keyboard: .up, in: app).maxY, keyboardCoverTop(in: app))

        logButton.tap()

        XCTAssertTrue(app.buttons["Set 2, 240x5@7"].appears(within: uiEventBudget))
        XCTAssertTrue(app.staticTexts["Set 3 of 3"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: uiEventBudget))
        assertLogSitsAboveTheRestPill(in: app)
    }

    @MainActor
    func testEveryWeightEditClosedWithDoneKeepsLogInReach() throws {
        let app = launchAnimated(options: [.offline])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: uiEventBudget))
        let card = app.otherElements["active-set-card"]
        let idleTop = restingFrame(of: card, keyboard: .down, in: app).minY
        var cardTops: [CGFloat] = []
        for _ in 1...3 {
            openWeightKeyboard(in: app)
            cardTops.append(restingFrame(of: card, keyboard: .up, in: app).minY)
            app.buttons["weight-keyboard-done"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: uiEventBudget))
        }
        XCTAssertEqual(cardTops[2], cardTops[0], accuracy: 1, "edit tops \(cardTops)")

        openWeightKeyboard(in: app)
        app.buttons["log-active-set-button"].tap()

        XCTAssertTrue(app.buttons["Set 1, 237.5x5@6"].appears(within: uiEventBudget))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: uiEventBudget))
        XCTAssertEqual(restingFrame(of: card, keyboard: .down, in: app).minY, idleTop, accuracy: 1, "a keyboard-up log leaves no keyboard inset")
    }

    @MainActor
    func testWeightKeyboardDoneKeepsTheSystemButtonFont() throws {
        let app = launchAnimated(options: [])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: uiEventBudget))
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

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: uiEventBudget))
        pairBackSquatWithBBRDL(in: app)

        let logButton = app.buttons["log-active-set-button"]
        openWeightKeyboard(in: app)
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "230")
        waitForLabel("Log 230 × 5 @6", on: logButton)
        XCTAssertLessThanOrEqual(restingFrame(of: logButton, keyboard: .up, in: app).maxY, keyboardCoverTop(in: app))

        logButton.tap()

        waitForLabel("BB RDL", on: app.staticTexts["stage-exercise-name"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: uiEventBudget))
    }

    @MainActor
    func testSupersetNameShedWhileWeightFieldIsFocusedLeavesTheAccessibilityTree() throws {
        let app = launchAnimated(options: [.offline])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: uiEventBudget))
        pairBackSquatWithBBRDL(in: app)
        let logButton = app.buttons["log-active-set-button"]
        logButton.tap()
        waitForLabel("BB RDL", on: app.staticTexts["stage-exercise-name"])
        XCTAssertTrue(app.staticTexts["Sync status: 1 unsynced"].appears(within: uiEventBudget))

        openWeightKeyboard(in: app)
        XCTAssertLessThanOrEqual(restingFrame(of: logButton, keyboard: .up, in: app).maxY, keyboardCoverTop(in: app))

        XCTAssertFalse(app.staticTexts["stage-exercise-name"].exists, "BB RDL's name is not drawn")
        XCTAssertFalse(app.buttons["superset-partner-name"].exists, "the & Back Squat switch is not drawn")

        app.buttons["weight-keyboard-done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: uiEventBudget))
        assertLogSitsAboveTheRestPill(in: app)
    }

    @MainActor
    func testTapOnNonInteractiveStageContentDismissesKeyboard() throws {
        let app = launchAnimated(options: [])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: uiEventBudget))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let hud = app.otherElements["session-header-hud"]
        let stageTop = restingFrame(of: hud, keyboard: .down, in: app).minY
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

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: uiEventBudget))
        openWeightKeyboard(in: app)
        XCTAssertFalse(app.otherElements["session-header-hud"].exists)

        tapWhenHittable(app.staticTexts["last-performed-line"])
        let historyTitle = app.staticTexts["Exercise History · last 5"]
        XCTAssertTrue(historyTitle.appears(within: uiEventBudget))
        historyTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)),
            withVelocity: .fast,
            thenHoldForDuration: 0
        )
        XCTAssertTrue(historyTitle.waitForNonExistence(timeout: uiEventBudget))

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
    XCTAssertTrue(app.staticTexts["This Session"].appears(within: uiEventBudget))
    tapWhenHittable(app.buttons["stage-queue-superset"])
    tapWhenHittable(app.buttons["stage-queue-row-exercise-1"])
    waitForLabel("& BB RDL", on: app.buttons["superset-partner-name"])
}

@MainActor
private func tapEmptyStageSpaceAboveExerciseName(in app: XCUIApplication, stageTop: CGFloat) {
    let nameTop = restingFrame(of: app.staticTexts["stage-exercise-name"], keyboard: .up, in: app).minY
    app.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: app.frame.midX, dy: (stageTop + nameTop) / 2))
        .tap()
}

@MainActor
private func centreTap(_ element: XCUIElement) {
    XCTAssertTrue(element.appears(within: uiEventBudget), "\(element) missing")
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
}

/// Opens the weight keyboard and returns once the active-set card rests above it.
@MainActor
private func openWeightKeyboard(in app: XCUIApplication) {
    app.buttons["weight-pill"].tap()
    waitForKeyboardOnScreen(in: app)
    _ = restingFrame(of: app.otherElements["active-set-card"], keyboard: .up, in: app)
}

@MainActor
private func waitForKeyboardOnScreen(in app: XCUIApplication) {
    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(
        keyboard.appears(within: uiEventBudget),
        "no software keyboard: keyboards \(app.keyboards.count), Done at \(app.buttons["weight-keyboard-done"].frame), "
            + "window \(app.frame)"
    )
    let deadline = Date().addingTimeInterval(uiEventBudget)
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
    XCTAssertTrue(keyboard.waitForNonExistence(timeout: uiEventBudget), "the keyboard is still up")
    XCTAssertFalse(keyboard.appears(within: 1), "the keyboard came back up")
}

private enum KeyboardState {
    case up, down
}

/// Reads `element` once the keyboard is `keyboard` and two reads 0.3 s apart agree. A still frame
/// alone is not enough: each `typeText` drops the keyboard below the window for most of a second,
/// and the active-set card rests at its idle place that whole time.
@MainActor
private func restingFrame(of element: XCUIElement, keyboard: KeyboardState, in app: XCUIApplication) -> CGRect {
    var last: CGRect?
    let deadline = Date().addingTimeInterval(uiEventBudget)
    while Date() < deadline {
        let frame = element.frame
        guard keyboardIs(keyboard, in: app) else {
            last = nil
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            continue
        }
        if frame == last { return frame }
        last = frame
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }
    XCTFail("\(element) not at rest with the keyboard \(keyboard) after \(uiEventBudget) s, at \(element.frame)")
    return element.frame
}

@MainActor
private func keyboardIs(_ state: KeyboardState, in app: XCUIApplication) -> Bool {
    let keyboard = app.keyboards.firstMatch
    switch state {
    case .up: return keyboard.exists && keyboard.frame.minY < app.frame.maxY
    case .down: return !keyboard.exists
    }
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
        restingFrame(of: app.buttons["log-active-set-button"], keyboard: .down, in: app).maxY,
        restingFrame(of: restPill, keyboard: .down, in: app).minY,
        "rest is back in the foot below the card"
    )
}

@MainActor
private func tapActiveSetCardHeaderBackground(in app: XCUIApplication) {
    let activeSetCard = app.otherElements["active-set-card"]
    XCTAssertTrue(activeSetCard.appears(within: uiEventBudget))
    activeSetCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14)).tap()
}
