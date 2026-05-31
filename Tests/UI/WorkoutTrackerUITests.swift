import XCTest

final class WorkoutTrackerUITests: XCTestCase {
    @MainActor
    func testFixtureDrivenCoreSessionFlow() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        XCTAssertTrue(app.buttons["session-location-button"].exists)

        app.buttons["rpe-pill"].tap()
        app.buttons["rpe-6"].tap()
        let logButton = app.buttons["log-active-set-button"]
        waitUntilEnabled(logButton)
        logButton.tap()

        waitForLabel("Weight, 252.5", on: app.buttons["weight-pill"])

        tapWhenReady(app.buttons["move-on-button"], in: app)
        let celebration = moveOnCelebration(in: app)
        XCTAssertTrue(celebration.waitForExistence(timeout: 3))
        waitForLabel("Week 1, Day 1 Done", on: celebration)
        waitForValue("5 Sets, 2 Exercises, 4 Left, Moved on with 4 left", on: celebration)
        assertMoveOnCelebrationCopyIsReadable(in: app)
        XCTAssertFalse(app.staticTexts["Back Squat"].exists)

        celebration.tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))

        app.buttons["session-location-button"].tap()
        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 3))

        app.buttons["Week 1, Day 3"].tap()
        waitForLabel("Open Block Overview for Week 1, Day 3", on: app.buttons["session-location-button"])
        XCTAssertTrue(app.buttons["go-back-current-session-button"].exists)
        XCTAssertTrue(app.buttons["make-current-session-button"].exists)

        app.buttons["make-current-session-button"].tap()
        XCTAssertFalse(app.buttons["go-back-current-session-button"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["make-current-session-button"].exists)
        waitForLabel("Open Block Overview for Week 1, Day 3", on: app.buttons["session-location-button"])

        tapWhenReady(app.buttons["move-on-button"], in: app)
        let secondCelebration = moveOnCelebration(in: app)
        XCTAssertTrue(secondCelebration.waitForExistence(timeout: 3))
        waitForLabel("Week 1, Day 3 Done", on: secondCelebration)
        secondCelebration.tap()
        XCTAssertTrue(app.staticTexts["Accessory W1 D4"].waitForExistence(timeout: 3))

        app.buttons["session-location-button"].tap()
        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 3))

        app.buttons["Week 1, Day 2"].tap()
        waitForLabel("Open Block Overview for Week 1, Day 2", on: app.buttons["session-location-button"])
        XCTAssertTrue(app.buttons["go-back-current-session-button"].exists)
        XCTAssertTrue(app.buttons["make-current-session-button"].exists)

        app.buttons["go-back-current-session-button"].tap()
        XCTAssertTrue(app.staticTexts["Accessory W1 D4"].waitForExistence(timeout: 3))
        waitForLabel("Open Block Overview for Week 1, Day 4", on: app.buttons["session-location-button"])
    }

    @MainActor
    func testActiveSetFieldFocusDismissesWithoutCardCancel() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)

        app.buttons["weight-pill"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        app.staticTexts["Set 1 of 3"].tap()

        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)

        app.buttons["rpe-pill"].tap()
        XCTAssertTrue(app.buttons["rpe-6"].waitForExistence(timeout: 3))

        app.staticTexts["Set 1 of 3"].tap()

        XCTAssertFalse(app.buttons["rpe-6"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
    }

    @MainActor
    func testRPEPickerHalfStepGestureSelectsHalfStepAndTapResetsToWhole() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        app.buttons["rpe-pill"].tap()
        let rpe6 = app.buttons["rpe-6"]
        XCTAssertTrue(rpe6.waitForExistence(timeout: 3))
        rpe6
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.45,
                thenDragTo: rpe6.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.8))
            )
        waitForLabel("Log 237.5×5@6.5", on: app.buttons["log-active-set-button"])

        app.buttons["rpe-pill"].tap()
        XCTAssertTrue(rpe6.waitForExistence(timeout: 3))
        rpe6.tap()

        waitForLabel("Log 237.5×5@6", on: app.buttons["log-active-set-button"])
    }

    @MainActor
    func testOverscrollRevealsSessionControlsInHeaderLayout() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["session-controls-settings-button"].exists)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            )

        let sessionControls = app.otherElements["session-controls"]
        let settingsButton = app.buttons["session-controls-settings-button"]
        let syncButton = app.buttons["session-controls-sync-button"]
        let locationButton = app.buttons["session-location-button"]
        let progressRail = app.otherElements["session-progress-rail"]
        let activeSetCard = app.otherElements["active-set-card"]

        XCTAssertTrue(sessionControls.waitForExistence(timeout: 3))
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        XCTAssertTrue(syncButton.exists)
        XCTAssertTrue(locationButton.exists)
        XCTAssertTrue(progressRail.exists)
        XCTAssertTrue(activeSetCard.exists)
        XCTAssertFalse(sessionControls.frame.intersects(locationButton.frame))
        XCTAssertFalse(sessionControls.frame.intersects(progressRail.frame))
        XCTAssertFalse(sessionControls.frame.intersects(activeSetCard.frame))
        XCTAssertLessThanOrEqual(sessionControls.frame.maxY, activeSetCard.frame.minY)

        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings-training-sheet-row"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Training Log"].exists)

        app.buttons["settings-training-sheet-row"].tap()
        XCTAssertTrue(app.staticTexts["Choose your training sheet"].waitForExistence(timeout: 3))
        app.buttons["sheet-picker-done-button"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        app.buttons["settings-done-button"].tap()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 3))
        let revealedSyncButton = app.buttons["session-controls-sync-button"]
        XCTAssertTrue(revealedSyncButton.waitForExistence(timeout: 3))
        revealedSyncButton.tap()
        XCTAssertTrue(app.staticTexts["Offline"].waitForExistence(timeout: 3))

        app.swipeUp()
        XCTAssertFalse(settingsButton.waitForExistence(timeout: 1))
    }

    @MainActor
    func testDeveloperToolsShowsDiagnosticsAndPreviewOnlyCelebration() throws {
        let app = launchFixtureApp(extraArguments: ["-UITEST_PENDING_WRITE"])

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            )
        app.buttons["session-controls-settings-button"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let trainingSheetRow = app.buttons["settings-training-sheet-row"]
        let developerToolsRow = app.buttons["settings-developer-tools-row"]
        let signOutButton = app.buttons["settings-sign-out-button"]
        XCTAssertTrue(trainingSheetRow.exists)
        XCTAssertTrue(developerToolsRow.exists)
        XCTAssertTrue(signOutButton.exists)
        XCTAssertLessThan(trainingSheetRow.frame.maxY, developerToolsRow.frame.minY)
        XCTAssertLessThan(developerToolsRow.frame.maxY, signOutButton.frame.minY)

        developerToolsRow.tap()
        XCTAssertTrue(app.navigationBars["Developer Tools"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Move On Celebration"].exists)
        XCTAssertTrue(app.staticTexts["Pending Sheet Writes"].exists)
        XCTAssertTrue(app.staticTexts["Back Squat"].exists)
        XCTAssertTrue(app.staticTexts["Block 27"].exists)
        XCTAssertTrue(app.staticTexts["Week 1"].exists)
        XCTAssertTrue(app.staticTexts["Day 1"].exists)
        XCTAssertTrue(app.staticTexts["Set 1"].exists)
        XCTAssertTrue(app.staticTexts["Notes"].exists)
        XCTAssertTrue(app.staticTexts["185x5@8"].exists)
        XCTAssertTrue(app.staticTexts["Pending"].exists)
        XCTAssertFalse(app.buttons["Discard"].exists)
        XCTAssertFalse(app.buttons["Delete"].exists)
        XCTAssertFalse(app.buttons["Reset Queue"].exists)

        app.buttons["developer-tools-force-celebration-button"].tap()
        let celebration = moveOnCelebration(in: app)
        XCTAssertTrue(celebration.waitForExistence(timeout: 3))
        waitForLabel("Week 1, Day 1 Done", on: celebration)
        celebration.tap()
        XCTAssertTrue(app.navigationBars["Developer Tools"].waitForExistence(timeout: 3))

        app.buttons["developer-tools-sync-button"].tap()
        XCTAssertTrue(app.staticTexts["Offline"].waitForExistence(timeout: 3))

        app.navigationBars["Developer Tools"].buttons["Settings"].tap()
        app.buttons["settings-done-button"].tap()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Bench Press"].exists)
    }

    @MainActor
    func testDeveloperToolsShowsCurrentSessionDebugInfoAndResetsOverride() throws {
        let app = launchFixtureApp(extraArguments: ["-UITEST_DEVELOPER_TOOLS", "-UITEST_CURRENT_SESSION_OVERRIDE"])

        XCTAssertTrue(app.navigationBars["Developer Tools"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Current Session Debug Info"].exists)
        XCTAssertEqual(app.staticTexts["current-session-debug-block-value"].label, "Block 27")
        XCTAssertEqual(app.staticTexts["current-session-debug-sheet-derived-value"].label, "Week 1, Day 1")
        XCTAssertEqual(app.staticTexts["current-session-debug-manual-override-value"].label, "Week 1, Day 3")
        XCTAssertEqual(app.staticTexts["current-session-debug-displayed-value"].label, "Week 1, Day 3")
        XCTAssertEqual(app.staticTexts["current-session-debug-resolved-value"].label, "Week 1, Day 3")
        XCTAssertEqual(
            app.staticTexts["current-session-debug-reason-value"].label,
            "Manual override is active for this Block."
        )
        XCTAssertTrue(app.staticTexts["current-session-debug-local-only-note"].exists)
        XCTAssertTrue(app.buttons["copy-current-session-debug-info-button"].exists)

        let resetButton = app.buttons["reset-current-session-override-button"]
        XCTAssertTrue(resetButton.exists)
        XCTAssertTrue(resetButton.isEnabled)
        resetButton.tap()

        XCTAssertEqual(app.staticTexts["current-session-debug-manual-override-value"].label, "None")
        XCTAssertEqual(app.staticTexts["current-session-debug-displayed-value"].label, "Week 1, Day 1")
        XCTAssertEqual(app.staticTexts["current-session-debug-resolved-value"].label, "Week 1, Day 1")
        XCTAssertFalse(resetButton.isEnabled)
    }

    @MainActor
    func testOpenExerciseMakeupFlowShowsLastPerformedAndLogsSet() throws {
        let app = launchFixtureApp(extraArguments: ["-UITEST_OPEN_EXERCISES"])

        app.swipeUp()
        let openBackSquat = app.buttons.containing(.staticText, identifier: "Back Squat").firstMatch
        tapWhenHittable(openBackSquat)

        XCTAssertTrue(app.buttons["go-back-current-session-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["make-current-session-button"].exists)
        XCTAssertTrue(app.staticTexts["Back Squat"].exists)
        XCTAssertTrue(app.staticTexts["Last Performed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["255x5@7"].exists)
        XCTAssertTrue(app.staticTexts["Block 26 · W4 D3"].exists)

        app.buttons["rpe-pill"].tap()
        app.buttons["rpe-7"].tap()
        waitForLabel("Log 252.5×5@7", on: app.buttons["log-active-set-button"])
        app.buttons["log-active-set-button"].tap()

        XCTAssertFalse(app.buttons["log-active-set-button"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSettingsSignOutReturnsToOnboarding() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            )

        app.buttons["session-controls-settings-button"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        app.buttons["settings-sign-out-button"].tap()

        XCTAssertTrue(app.staticTexts["Connect your training sheet"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSettingsSignOutWithPendingWritesRequiresConfirmation() throws {
        let app = launchFixtureApp(extraArguments: ["-UITEST_PENDING_WRITE"])

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            )

        app.buttons["session-controls-settings-button"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        app.buttons["settings-sign-out-button"].tap()
        XCTAssertTrue(app.alerts["You have unsynced changes. Sign out anyway?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["settings-sign-out-button"].tap()
        XCTAssertTrue(app.alerts["You have unsynced changes. Sign out anyway?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Sign Out"].tap()

        XCTAssertTrue(app.staticTexts["Connect your training sheet"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSheetSwitchWithPendingWritesShowsConfirmation() throws {
        let app = launchFixtureApp(extraArguments: ["-UITEST_PENDING_WRITE"])

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            )

        app.buttons["session-controls-settings-button"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        app.buttons["settings-training-sheet-row"].tap()
        XCTAssertTrue(app.staticTexts["Replacement Training Log"].waitForExistence(timeout: 3))
        app.staticTexts["Replacement Training Log"].tap()

        XCTAssertTrue(app.alerts["You have unsynced changes. Switch anyway?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()

        XCTAssertTrue(app.staticTexts["Replacement Training Log"].waitForExistence(timeout: 3))
        app.staticTexts["Replacement Training Log"].tap()
        XCTAssertTrue(app.alerts["You have unsynced changes. Switch anyway?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Switch Anyway"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Replacement Training Log"].waitForExistence(timeout: 3))

        tapWhenHittable(app.buttons["settings-done-button"])
        XCTAssertTrue(app.staticTexts["Replacement Squat"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchFixtureApp(extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_FIXTURE", "-UITEST_SESSION", "-UITEST_FULL_BLOCK"] + extraArguments
        app.launch()
        return app
    }
}

@MainActor
private func tapWhenReady(_ element: XCUIElement, in app: XCUIApplication) {
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    if element.isHittable {
        element.tap()
        return
    }

    app.swipeUp()
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    element.tap()
}

@MainActor
private func waitForLabel(_ label: String, on element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 3), "Expected element for label '\(label)' to exist")
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if element.label == label {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to have label '\(label)', got '\(element.label)'")
}

@MainActor
private func waitForValue(_ value: String, on element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if element.value as? String == value {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to have value '\(value)', got '\(String(describing: element.value))'")
}

@MainActor
private func waitUntilEnabled(_ element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if element.isEnabled {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to become enabled")
}

@MainActor
private func tapWhenHittable(_ element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if element.isHittable {
            element.tap()
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to become hittable")
}

@MainActor
private func moveOnCelebration(in app: XCUIApplication) -> XCUIElement {
    let button = app.buttons["move-on-celebration"]
    if button.waitForExistence(timeout: 1) {
        return button
    }

    let scrollView = app.scrollViews["move-on-celebration"]
    if scrollView.waitForExistence(timeout: 1) {
        return scrollView
    }

    let element = app.otherElements["move-on-celebration"]
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    return element
}

@MainActor
private func assertMoveOnCelebrationCopyIsReadable(in app: XCUIApplication) {
    let approvedQuotes = ["You're fucking amazing.", "God damn!", "Get it girl!", "Shake it!"]
    let quote = app.staticTexts["move-on-celebration-quote"]
    let title = app.staticTexts["move-on-celebration-title"]
    let subline = app.staticTexts["move-on-celebration-subline"]
    let stats = [
        app.staticTexts["move-on-celebration-sets-value"],
        app.staticTexts["move-on-celebration-exercises-value"],
        app.staticTexts["move-on-celebration-left-value"],
        app.staticTexts["move-on-celebration-sets-label"],
        app.staticTexts["move-on-celebration-exercises-label"],
        app.staticTexts["move-on-celebration-left-label"]
    ]
    let hint = app.staticTexts["move-on-celebration-hint"]
    let windowFrame = app.windows.element(boundBy: 0).frame

    XCTAssertTrue(quote.waitForExistence(timeout: 6))
    XCTAssertTrue(approvedQuotes.contains(quote.label))
    let selectedQuote = quote.label
    RunLoop.current.run(until: Date().addingTimeInterval(3))
    XCTAssertEqual(quote.label, selectedQuote)

    for element in [quote, title, subline, hint] + stats {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(windowFrame.contains(element.frame), "\(element) is clipped outside \(windowFrame)")
    }

    XCTAssertLessThanOrEqual(quote.frame.maxY, title.frame.minY)
    XCTAssertLessThanOrEqual(title.frame.maxY, subline.frame.minY)
    XCTAssertLessThan(stats.map(\.frame.maxY).max() ?? 0, hint.frame.minY)
}

final class WorkoutTrackerLongSessionUITests: XCTestCase {
    @MainActor
    func testLongSessionCardsStayAliveAndProgrammaticSupersetScrollLands() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["active-set-card"].exists)

        app.buttons["rpe-pill"].tap()
        app.buttons["rpe-6"].tap()
        let logButton = app.buttons["log-active-set-button"]
        waitUntilEnabled(logButton)
        logButton.tap()

        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Bench Press"].isHittable)

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Farmer Carry"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchFixtureApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_FIXTURE", "-UITEST_SESSION", "-UITEST_LONG_SESSION"]
        app.launch()
        return app
    }
}

final class WorkoutTrackerSkipUITests: XCTestCase {
    @MainActor
    func testIncompleteSetLogCanStillBeSkippedWithHold() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log", on: logButton)

        logButton.press(forDuration: 1.0)

        XCTAssertTrue(app.buttons["Set 1, skip"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchFixtureApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_FIXTURE", "-UITEST_SESSION", "-UITEST_FULL_BLOCK"]
        app.launch()
        return app
    }

    @MainActor
    private func waitForLabel(_ label: String, on element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Expected element for label '\(label)' to exist")
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if element.label == label {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Expected \(element) to have label '\(label)', got '\(element.label)'")
    }
}
