import XCTest

final class WorkoutTrackerUITests: XCTestCase {
    @MainActor
    func testFixtureDrivenCoreSessionFlow() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        XCTAssertTrue(app.buttons["session-location-button"].exists)

        app.buttons["rpe-6"].tap()
        let logButton = app.buttons["log-active-set-button"]
        waitUntilEnabled(logButton)
        logButton.tap()

        waitForLabel("Weight, 252.5", on: app.buttons["weight-pill"])

        tapWhenReady(app.buttons["move-on-button"], in: app)
        let celebration = moveOnCelebration(in: app)
        XCTAssertTrue(celebration.waitForExistence(timeout: 3))
        waitForLabel("Week 1, Day 1", on: celebration)
        waitForValueContaining("5 Sets, 2 Exercises, 4 Left", on: celebration)
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
        waitForLabel("Week 1, Day 3", on: secondCelebration)
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
    func testMoveOnCelebrationLongQuoteKeepsStatsAndHintVisible() throws {
        let app = launchFixtureApp(extraArguments: ["-UITEST_LONG_CELEBRATION_QUOTE"])

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        tapWhenReady(app.buttons["move-on-button"], in: app)
        let celebration = moveOnCelebration(in: app)
        XCTAssertTrue(celebration.waitForExistence(timeout: 3))
        waitForLabel("Week 1, Day 1", on: celebration)
        waitForValueContaining("5 Sets, 2 Exercises, 5 Left", on: celebration)
        XCTAssertEqual(
            app.staticTexts["move-on-celebration-quote"].label,
            "Strong work is still strong when you leave a few Sets for later."
        )
        assertMoveOnCelebrationCopyIsReadable(in: app)
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

        dismissActiveSetInputBackground(in: app)

        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)

        XCTAssertTrue(app.buttons["rpe-6"].waitForExistence(timeout: 3))
        app.buttons["rpe-7"].tap()
        waitForLabel("Log 237.5×5@7", on: app.buttons["log-active-set-button"])
        app.buttons["rpe-6"].tap()
        waitForLabel("Log 237.5×5@6", on: app.buttons["log-active-set-button"])
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
    }

    @MainActor
    func testRPEScaleSelectsHalfStepAndTapResetsToWhole() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        let rpe6 = app.buttons["rpe-6"]
        XCTAssertTrue(rpe6.waitForExistence(timeout: 3))
        app.buttons["rpe-6.5"].tap()
        waitForLabel("Log 237.5×5@6.5", on: app.buttons["log-active-set-button"])

        XCTAssertTrue(rpe6.waitForExistence(timeout: 3))
        rpe6.tap()

        waitForLabel("Log 237.5×5@6", on: app.buttons["log-active-set-button"])
    }

    @MainActor
    func testOverscrollRevealsSessionControlsInHeaderLayout() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["session-controls-settings-button"].exists)

        let settingsButton = revealSessionControlsAndSettingsButton(in: app)

        let sessionControls = app.otherElements["session-controls"]
        let locationButton = app.buttons["session-location-button"]
        let progressRail = app.otherElements["session-progress-rail"]
        let activeSetCard = app.otherElements["active-set-card"]

        XCTAssertTrue(sessionControls.exists)
        XCTAssertTrue(settingsButton.exists)
        XCTAssertFalse(app.buttons["session-controls-sync-button"].exists)
        XCTAssertTrue(locationButton.exists)
        XCTAssertTrue(progressRail.exists)
        XCTAssertTrue(activeSetCard.exists)
        XCTAssertFalse(sessionControls.frame.intersects(locationButton.frame))
        XCTAssertFalse(sessionControls.frame.intersects(progressRail.frame))
        XCTAssertFalse(sessionControls.frame.intersects(activeSetCard.frame))
        XCTAssertLessThanOrEqual(sessionControls.frame.maxY, activeSetCard.frame.minY)

        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        let trainingSheetRow = app.buttons["settings-training-sheet-row"]
        let syncNowButton = app.buttons["settings-sync-now-button"]
        let developerToolsRow = app.buttons["settings-developer-tools-row"]
        XCTAssertTrue(trainingSheetRow.exists)
        XCTAssertTrue(syncNowButton.exists)
        XCTAssertTrue(developerToolsRow.exists)
        XCTAssertTrue(app.staticTexts["Fixture Training Log"].exists)
        XCTAssertLessThan(trainingSheetRow.frame.maxY, syncNowButton.frame.minY)
        XCTAssertLessThan(syncNowButton.frame.maxY, developerToolsRow.frame.minY)

        trainingSheetRow.tap()
        XCTAssertTrue(app.staticTexts["Choose your training sheet"].waitForExistence(timeout: 3))
        app.buttons["sheet-picker-done-button"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        app.buttons["settings-sync-now-button"].tap()
        XCTAssertTrue(app.staticTexts["Offline"].waitForExistence(timeout: 3))

        app.buttons["settings-done-button"].tap()
        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 3))

        waitForNonExistence(settingsButton, timeout: 1)

        let pinnedSettingsButton = revealSessionControlsAndSettingsButton(in: app)
        app.swipeUp()
        waitForNonExistence(pinnedSettingsButton, timeout: 1)
    }

    @MainActor
    func testOrdinaryBounceAndPrecommitReleaseDoNotPinSessionSettings() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        pullSessionHeader(in: app, endY: 0.34)
        XCTAssertFalse(app.buttons["session-controls-settings-button"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.otherElements["session-controls"].exists)

        pullSessionHeader(in: app, endY: 0.43)
        XCTAssertFalse(app.buttons["session-controls-settings-button"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.otherElements["session-controls"].exists)
    }

    @MainActor
    func testPinnedSessionSettingsDismissesAfterIdle() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        let settingsButton = revealSessionControlsAndSettingsButton(in: app)

        waitForNonExistence(settingsButton, timeout: 4)
    }

    @MainActor
    func testNonCurrentSessionChromeHidesCurrentSessionControlsThroughOverscroll() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        app.buttons["session-location-button"].tap()
        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 3))

        app.buttons["Week 1, Day 3"].tap()
        waitForLabel("Open Block Overview for Week 1, Day 3", on: app.buttons["session-location-button"])

        XCTAssertTrue(app.buttons["go-back-current-session-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["make-current-session-button"].exists)
        XCTAssertFalse(app.staticTexts["Go back"].exists)
        XCTAssertFalse(app.staticTexts["Make Current"].exists)
        XCTAssertFalse(app.buttons["session-controls-settings-button"].exists)
        XCTAssertFalse(app.buttons["session-controls-sync-button"].exists)

        overPullSessionHeader(in: app)

        XCTAssertFalse(app.buttons["session-controls-settings-button"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["session-controls-sync-button"].exists)
        XCTAssertFalse(app.otherElements["session-controls"].exists)
        XCTAssertTrue(app.buttons["go-back-current-session-button"].exists)
        XCTAssertTrue(app.buttons["make-current-session-button"].exists)
    }

    @MainActor
    func testDeveloperToolsShowsDiagnosticsAndPreviewOnlyCelebration() throws {
        let app = launchFixtureApp(extraArguments: ["-UITEST_PENDING_WRITE"])

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        revealSessionControlsAndSettingsButton(in: app).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let trainingSheetRow = app.buttons["settings-training-sheet-row"]
        let syncNowButton = app.buttons["settings-sync-now-button"]
        let developerToolsRow = app.buttons["settings-developer-tools-row"]
        let signOutButton = app.buttons["settings-sign-out-button"]
        XCTAssertTrue(trainingSheetRow.exists)
        XCTAssertTrue(syncNowButton.exists)
        XCTAssertTrue(developerToolsRow.exists)
        XCTAssertTrue(signOutButton.exists)
        XCTAssertLessThan(trainingSheetRow.frame.maxY, syncNowButton.frame.minY)
        XCTAssertLessThan(syncNowButton.frame.maxY, developerToolsRow.frame.minY)
        XCTAssertLessThan(developerToolsRow.frame.maxY, signOutButton.frame.minY)

        developerToolsRow.tap()
        XCTAssertTrue(app.navigationBars["Developer Tools"].waitForExistence(timeout: 3))
        assertDeveloperToolsActionsAndDiagnosticsLayout(in: app)

        app.buttons["developer-tools-force-celebration-button"].tap()
        let celebration = moveOnCelebration(in: app)
        XCTAssertTrue(celebration.waitForExistence(timeout: 3))
        waitForLabel("Week 1, Day 1", on: celebration)
        celebration.tap()
        XCTAssertTrue(app.navigationBars["Developer Tools"].waitForExistence(timeout: 3))

        assertDeveloperToolsSyncStatusFollowsSyncButton(in: app)

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
        let copyButton = app.buttons["copy-current-session-debug-info-button"]
        XCTAssertTrue(copyButton.exists)

        let resetButton = app.buttons["reset-current-session-override-button"]
        XCTAssertTrue(resetButton.exists)
        XCTAssertLessThan(copyButton.frame.maxX, resetButton.frame.minX)
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

        app.buttons["rpe-7"].tap()
        waitForLabel("Log 252.5×5@7", on: app.buttons["log-active-set-button"])
        app.buttons["log-active-set-button"].tap()

        XCTAssertFalse(app.buttons["log-active-set-button"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSettingsSignOutReturnsToOnboarding() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        revealSessionControlsAndSettingsButton(in: app).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        app.buttons["settings-sign-out-button"].tap()

        XCTAssertTrue(app.staticTexts["Connect your training sheet"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSettingsSignOutWithPendingWritesRequiresConfirmation() throws {
        let app = launchFixtureApp(extraArguments: ["-UITEST_PENDING_WRITE"])

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        revealSessionControlsAndSettingsButton(in: app).tap()
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

        revealSessionControlsAndSettingsButton(in: app).tap()
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

final class WorkoutTrackerAppearanceUITests: XCTestCase {
    @MainActor
    func testDarkAppearanceCoversCurrentSessionAndSettingsSurfaces() throws {
        let app = launchFixtureApp(appearance: "dark")

        assertCurrentSessionAppearanceCoverage(in: app)
        revealSessionControlsAndSettingsButton(in: app).tap()
        assertSettingsAppearanceCoverage(in: app)
    }

    @MainActor
    func testLightAppearanceCoversCurrentSessionAndSettingsSurfaces() throws {
        let app = launchFixtureApp(appearance: "light")

        assertCurrentSessionAppearanceCoverage(in: app)
        revealSessionControlsAndSettingsButton(in: app).tap()
        assertSettingsAppearanceCoverage(in: app)
    }

    @MainActor
    func testSettingsFixtureRouteLaunchesSettingsForScreenshotCoverage() throws {
        let app = launchSettingsFixtureApp(appearance: "light")

        assertSettingsAppearanceCoverage(in: app)
    }

    @MainActor
    func testSettingsAppearancePickerSwitchesManualLightAndDark() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        revealSessionControlsAndSettingsButton(in: app).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let picker = app.segmentedControls["settings-appearance-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["System"].exists)
        XCTAssertTrue(app.buttons["Light"].exists)
        XCTAssertTrue(app.buttons["Dark"].exists)
        XCTAssertFalse(app.buttons["Black"].exists)
        XCTAssertFalse(app.buttons["Mint Green"].exists)
        XCTAssertFalse(app.buttons["Blue Light"].exists)

        app.buttons["Light"].tap()
        app.buttons["Dark"].tap()

        app.buttons["settings-done-button"].tap()
        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLightAppearanceMoveOnCelebrationRendersAndDismisses() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        revealSessionControlsAndSettingsButton(in: app).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let picker = app.segmentedControls["settings-appearance-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        app.buttons["Light"].tap()
        app.buttons["settings-done-button"].tap()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 3))
        tapWhenReady(app.buttons["move-on-button"], in: app)

        let celebration = moveOnCelebration(in: app)
        XCTAssertTrue(celebration.waitForExistence(timeout: 3))
        waitForLabel("Week 1, Day 1", on: celebration)
        assertMoveOnCelebrationCopyIsReadable(in: app)

        celebration.tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
        XCTAssertFalse(celebration.exists)
    }

    @MainActor
    private func launchFixtureApp(appearance: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_FIXTURE", "-UITEST_SESSION", "-UITEST_FULL_BLOCK"]
        if let appearance {
            app.launchArguments += ["-UITEST_APPEARANCE", appearance]
        }
        app.launch()
        return app
    }

    @MainActor
    private func launchSettingsFixtureApp(appearance: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_FIXTURE", "-UITEST_SETTINGS", "-UITEST_APPEARANCE", appearance]
        app.launch()
        return app
    }

    @MainActor
    private func assertCurrentSessionAppearanceCoverage(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["active-set-card"].exists)
        XCTAssertTrue(app.buttons["weight-pill"].exists)
        XCTAssertTrue(app.buttons["reps-pill"].exists)
        XCTAssertTrue(app.buttons["rpe-6"].exists)
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.buttons["session-location-button"].exists)
        XCTAssertTrue(app.staticTexts["Last Performed"].exists)
    }

    @MainActor
    private func assertSettingsAppearanceCoverage(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.segmentedControls["settings-appearance-picker"].exists)
        XCTAssertTrue(app.buttons["settings-training-sheet-row"].exists)
        XCTAssertTrue(app.buttons["settings-sync-now-button"].exists)
        XCTAssertTrue(app.buttons["settings-developer-tools-row"].exists)
        XCTAssertTrue(app.buttons["settings-sign-out-button"].exists)
        XCTAssertTrue(app.staticTexts["Fixture Training Log"].exists)
        XCTAssertFalse(app.buttons["Black"].exists)
        XCTAssertFalse(app.buttons["Mint Green"].exists)
        XCTAssertFalse(app.buttons["Blue Light"].exists)
    }
}

@MainActor
private func assertDeveloperToolsActionsAndDiagnosticsLayout(in app: XCUIApplication) {
    XCTAssertTrue(app.staticTexts["Actions"].exists)
    XCTAssertFalse(app.staticTexts["Move On Celebration"].exists)
    XCTAssertTrue(app.staticTexts["Pending Sheet Writes"].exists)
    XCTAssertTrue(app.buttons["developer-tools-force-celebration-button"].exists)
    XCTAssertTrue(app.buttons["developer-tools-sync-button"].exists)
    XCTAssertLessThan(
        app.staticTexts["Current Session Debug Info"].frame.maxY,
        app.staticTexts["Pending Sheet Writes"].frame.minY
    )
    XCTAssertLessThan(
        app.staticTexts["Pending Sheet Writes"].frame.maxY,
        app.staticTexts["Actions"].frame.minY
    )
    XCTAssertLessThan(
        app.buttons["developer-tools-force-celebration-button"].frame.maxY,
        app.buttons["developer-tools-sync-button"].frame.minY
    )
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
}

@MainActor
private func assertDeveloperToolsSyncStatusFollowsSyncButton(in app: XCUIApplication) {
    let syncButton = app.buttons["developer-tools-sync-button"]
    syncButton.tap()
    XCTAssertTrue(app.staticTexts["Offline"].firstMatch.waitForExistence(timeout: 3))
    let syncStatusBanner = app.descendants(matching: .any)["developer-tools-sync-status-banner"].firstMatch
    XCTAssertTrue(syncStatusBanner.waitForExistence(timeout: 3))
    XCTAssertLessThan(syncButton.frame.maxY, syncStatusBanner.frame.minY)
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
private func dismissActiveSetInputBackground(in app: XCUIApplication) {
    let activeSetCard = app.otherElements["active-set-card"]
    XCTAssertTrue(activeSetCard.waitForExistence(timeout: 3))
    activeSetCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56)).tap()
}

@MainActor
private func revealSessionControlsAndSettingsButton(in app: XCUIApplication) -> XCUIElement {
    let settingsButton = app.buttons["session-controls-settings-button"]
    if settingsButton.waitForExistence(timeout: 1), settingsButton.isHittable {
        return settingsButton
    }

    overPullSessionHeader(in: app)

    XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if settingsButton.isHittable {
            return settingsButton
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected session controls settings button to become hittable")
    return settingsButton
}

@MainActor
private func overPullSessionHeader(in app: XCUIApplication) {
    pullSessionHeader(in: app, endY: 0.75)
}

@MainActor
private func pullSessionHeader(in app: XCUIApplication, endY: CGFloat) {
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        .press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        )
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
private func waitForValueContaining(_ value: String, on element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 3))
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if let elementValue = element.value as? String, elementValue.contains(value) {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to have value containing '\(value)', got '\(String(describing: element.value))'")
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
private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if !element.exists {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    XCTFail("Expected \(element) to stop existing")
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
    let approvedQuotes = [
        "You're fucking amazing.",
        "God damn!",
        "Get it girl!",
        "Shake it!",
        "Strong work is still strong when you leave a few Sets for later."
    ]
    let context = app.staticTexts["move-on-celebration-context"]
    let logo = app.staticTexts["move-on-celebration-logo"]
    let quote = app.staticTexts["move-on-celebration-quote"]
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

    for element in [context, logo, quote, hint] + stats {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(windowFrame.contains(element.frame), "\(element) is clipped outside \(windowFrame)")
    }

    XCTAssertEqual(logo.label, "TFN")
    XCTAssertFalse(app.staticTexts["move-on-celebration-title"].exists)
    XCTAssertFalse(app.staticTexts["move-on-celebration-subline"].exists)
    XCTAssertFalse(app.staticTexts["Day 1 Done"].exists)
    XCTAssertFalse(app.staticTexts["Moved on with 4 left"].exists)
    XCTAssertLessThanOrEqual(context.frame.maxY, logo.frame.minY)
    XCTAssertLessThanOrEqual(logo.frame.maxY, quote.frame.minY)
    XCTAssertLessThanOrEqual(quote.frame.maxY, stats.map(\.frame.minY).min() ?? quote.frame.maxY)
    XCTAssertLessThan(stats[0].frame.maxX, stats[1].frame.minX)
    XCTAssertLessThan(stats[1].frame.maxX, stats[2].frame.minX)
    XCTAssertLessThan(stats.map(\.frame.maxY).max() ?? 0, hint.frame.minY)
}

final class WorkoutTrackerLongSessionUITests: XCTestCase {
    @MainActor
    func testLongSessionCardsStayAliveAndProgrammaticSupersetScrollLands() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["active-set-card"].exists)

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
    func testActiveSetCanBeSkippedWithHold() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let logButton = app.buttons["log-active-set-button"]
        waitUntilEnabled(logButton)

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
}
