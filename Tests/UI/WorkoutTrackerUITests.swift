import XCTest

final class WorkoutTrackerInteractionUITests: XCTestCase {
    @MainActor
    func testActiveSetFieldFocusDismissesWithoutCardCancel() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)

        app.buttons["weight-pill"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        tapActiveSetCardHeaderBackground(in: app)

        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)

        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
    }

    @MainActor
    func testActiveSetLogButtonSubmitsFromBackgroundWhileWeightFieldIsFocused() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)

        app.buttons["rpe-6"].tap()
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 237.5×5@6", on: logButton)

        app.buttons["weight-pill"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        logButton.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()

        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["Set 1, 237.5x5@6"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.navigationBars["Developer Tools"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Current Session Debug Info"].exists)
        XCTAssertTrue(app.staticTexts["Pending Sheet Writes"].exists)
        XCTAssertTrue(app.staticTexts["Actions"].exists)
        XCTAssertTrue(app.buttons["developer-tools-force-celebration-button"].exists)
        XCTAssertTrue(app.buttons["developer-tools-sync-button"].exists)

        app.navigationBars["Developer Tools"].buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testBuildIdentityFooterShowsAndCopiesOnTap() throws {
        let app = launchSettingsFixtureApp()

        let footer = app.buttons["settings-build-identity-footer"]
        XCTAssertTrue(footer.waitForExistence(timeout: 3))

        // Local (unstamped) test builds surface the version pair plus a "local build" note.
        XCTAssertTrue(footer.label.contains("local build"))

        footer.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOpenExerciseMakeupFlowShowsLastPerformedAndLogsSet() throws {
        let app = launchFixtureApp(options: [.openExercises])

        app.buttons["stage-queue-button"].tap()
        let openBackSquat = app.buttons.containing(.staticText, identifier: "Back Squat").firstMatch
        tapWhenHittable(openBackSquat)

        XCTAssertTrue(app.buttons["go-back-current-session-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["make-current-session-button"].exists)
        XCTAssertTrue(app.staticTexts["Back Squat"].exists)
        let lastPerformed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Last Performed 245x5@6, 255x5@7")
        ).firstMatch
        XCTAssertTrue(lastPerformed.waitForExistence(timeout: 3))
        XCTAssertTrue(lastPerformed.label.contains("Block 26 · W4 D3"))

        app.buttons["rpe-7"].tap()
        waitForLabel("Log 252.5×5@7", on: app.buttons["log-active-set-button"])
        app.buttons["log-active-set-button"].tap()

        XCTAssertFalse(app.buttons["log-active-set-button"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCompletionStageListsOpenExercisesAndNavigatesToSource() throws {
        let app = launchWorkoutApp(
            fixture: .completedSessionWithOpenExercises,
            options: [.disableCelebrationBloom]
        )

        XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 5))

        let openBackSquat = app.buttons.containing(.staticText, identifier: "Back Squat").firstMatch
        XCTAssertTrue(openBackSquat.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["move-on-button"].exists)

        tapWhenHittable(openBackSquat)

        XCTAssertTrue(app.buttons["go-back-current-session-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Back Squat"].exists)
    }

    @MainActor
    func testSettingsRevealGestureOpensSettings() throws {
        let app = launchFixtureApp(options: [.pendingWrite])

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["session-controls-settings-button"].exists)

        let settingsButton = revealSessionControlsAndSettingsButton(in: app)
        XCTAssertTrue(app.otherElements["session-controls"].exists)
        XCTAssertTrue(settingsButton.exists)
        XCTAssertTrue(settingsButton.isHittable)
        XCTAssertFalse(app.buttons["session-controls-sync-button"].exists)

        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Fixture Training Log"].exists)
    }

    @MainActor
    func testTappingLastPerformedOpensExerciseHistorySheet() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        let lastPerformed = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Last Performed 245x5@6, 255x5@7")
        ).firstMatch
        XCTAssertTrue(lastPerformed.waitForExistence(timeout: 3))
        tapWhenHittable(lastPerformed)

        // The quiet Exercise History sheet, seeded with deeper Back Squat history.
        XCTAssertTrue(app.staticTexts["Exercise History · last 5"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["BLOCK 26"].exists)
        XCTAssertTrue(app.staticTexts["BLOCK 25"].exists)
        // Grouped rows carry their Sets: the deeper Block 26 entry renders its formatted line.
        let deeperRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "235×5")
        ).firstMatch
        XCTAssertTrue(deeperRow.waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchFixtureApp(options: [WorkoutUITestFixtureOption] = []) -> XCUIApplication {
        launchWorkoutApp(
            fixture: .currentSession,
            options: [.disableCelebrationBloom] + options
        )
    }

    @MainActor
    private func launchSettingsFixtureApp(options: [WorkoutUITestFixtureOption] = []) -> XCUIApplication {
        launchWorkoutApp(
            fixture: .settings,
            options: [.disableCelebrationBloom] + options
        )
    }
}

final class WorkoutTrackerAppearanceUITests: XCTestCase {
    @MainActor
    func testSettingsAppearancePickerIsReachableAndWired() throws {
        let app = launchSettingsFixtureApp()

        let picker = app.segmentedControls["settings-appearance-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["System"].exists)
        XCTAssertTrue(app.buttons["Light"].exists)
        // "Dark" has left the product vocabulary — the third appearance is Night (DESIGN.md §5.9).
        XCTAssertTrue(app.buttons["Night"].exists)
        XCTAssertFalse(app.buttons["Dark"].exists)
        XCTAssertFalse(app.buttons["Black"].exists)
        XCTAssertFalse(app.buttons["Mint Green"].exists)
        XCTAssertFalse(app.buttons["Blue Light"].exists)

        app.buttons["Light"].tap()
        app.buttons["Night"].tap()
    }

    @MainActor
    private func launchSettingsFixtureApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .settings)
    }
}

final class WorkoutTrackerOnboardingSwitchUITests: XCTestCase {
    /// Covers the onboarding sheet-selection path, which previously wrote the selection straight to
    /// settings without syncing. It must now run the safe switch transaction: auto-sync the newly
    /// selected sheet and land on its freshly parsed session, never presenting the stale cached Block.
    @MainActor
    func testOnboardingSheetSelectionAutoSyncsAndReplacesStaleCachedBlock() throws {
        let app = launchWorkoutApp(fixture: .onboarding, options: [.disableCelebrationBloom])

        // Signed in, but no spreadsheet selected yet — onboarding shows the sheet picker.
        XCTAssertTrue(app.staticTexts["Choose your training sheet"].waitForExistence(timeout: 5))
        // The seeded (stale) Block is never shown while onboarding.
        XCTAssertFalse(app.staticTexts["Back Squat"].exists)

        let replacementRow = app.buttons["Replacement Training Log"]
        XCTAssertTrue(replacementRow.waitForExistence(timeout: 5))
        replacementRow.tap()

        // Auto-synced the newly selected sheet (no manual re-sync) and advanced to its session.
        XCTAssertTrue(app.staticTexts["Replacement Squat"].waitForExistence(timeout: 10))
        // The stale cached Block's exercise is never presented for the newly selected sheet.
        XCTAssertFalse(app.staticTexts["Back Squat"].exists)
    }
}

@MainActor
private func tapActiveSetCardHeaderBackground(in app: XCUIApplication) {
    let activeSetCard = app.otherElements["active-set-card"]
    XCTAssertTrue(activeSetCard.waitForExistence(timeout: 3))
    activeSetCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14)).tap()
}

@MainActor
private func revealSessionControlsAndSettingsButton(in app: XCUIApplication) -> XCUIElement {
    let settingsButton = app.buttons["session-controls-settings-button"]
    if settingsButton.waitForExistence(timeout: 1), settingsButton.isHittable {
        return settingsButton
    }

    overPullSessionHeader(in: app)
    if !settingsButton.waitForExistence(timeout: 3) {
        overPullSessionBody(in: app)
    }

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
private func overPullSessionBody(in app: XCUIApplication) {
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
    start.press(forDuration: 0.1, thenDragTo: end)
}

@MainActor
private func pullSessionHeader(in app: XCUIApplication, endY: CGFloat) {
    let headerHUD = app.otherElements["session-header-hud"]
    XCTAssertTrue(headerHUD.waitForExistence(timeout: 3))
    let start = app.coordinate(
        withNormalizedOffset: CGVector(
            dx: headerHUD.frame.midX / app.frame.width,
            dy: headerHUD.frame.midY / app.frame.height
        )
    )
    start
        .press(
            forDuration: 0.1,
            thenDragTo: start.withOffset(CGVector(dx: 0, dy: app.frame.height * (endY - 0.25)))
        )
}

@MainActor
private func assertMoveOnCelebrationIsUsable(_ celebration: XCUIElement, in app: XCUIApplication) {
    let quote = app.staticTexts["move-on-celebration-quote"]
    let hint = app.staticTexts["move-on-celebration-hint"]
    let windowFrame = app.windows.element(boundBy: 0).frame

    XCTAssertTrue(quote.waitForExistence(timeout: 6))
    XCTAssertFalse(quote.label.isEmpty)
    assertElementIsMostlyVisible(quote, in: windowFrame)
    XCTAssertTrue(hint.waitForExistence(timeout: 3))
    assertElementIsMostlyVisible(hint, in: windowFrame)
    XCTAssertTrue(celebration.isHittable)
}

private func assertElementIsMostlyVisible(
    _ element: XCUIElement,
    in visibleFrame: CGRect,
    minimumVisibleRatio: CGFloat = 0.9
) {
    let elementFrame = element.frame
    let elementArea = elementFrame.width * elementFrame.height
    XCTAssertGreaterThan(elementArea, 0, "\(element) has no readable bounds")
    guard elementArea > 0 else { return }

    let clippedFrame = visibleFrame.intersection(elementFrame)
    let visibleArea = clippedFrame.width * clippedFrame.height
    XCTAssertGreaterThanOrEqual(
        visibleArea / elementArea,
        minimumVisibleRatio,
        "\(element) is not readable within \(visibleFrame)"
    )
}

final class WorkoutTrackerLongSessionUITests: XCTestCase {
    @MainActor
    func testLongSessionStageAdvancesAfterLogAndShowsUpNext() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["active-set-card"].exists)
        XCTAssertTrue(app.buttons["stage-up-next"].staticTexts["Bench Press"].exists)

        app.buttons["rpe-6"].tap()
        app.buttons["weight-pill"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.typeText("225")

        tapActiveSetCardHeaderBackground(in: app)
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 225×5@6", on: logButton)
        tapWhenHittable(logButton)

        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.buttons["stage-up-next"].staticTexts["Chest-Supported Row"].waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testLongSessionQueueListsEveryExerciseAndJumpLandsOnStage() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        let queueButton = app.buttons["stage-queue-button"]
        waitForLabel("1 of 8", on: queueButton)
        queueButton.tap()

        XCTAssertTrue(app.staticTexts["This Session"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["stage-queue-row-exercise-0"].isEnabled)

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

        XCTAssertTrue(app.staticTexts["Farmer Carry"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Tall posture."].exists)
    }

    @MainActor
    private func launchFixtureApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .longSession)
    }
}

final class WorkoutTrackerSupersetUITests: XCTestCase {
    @MainActor
    func testQueuePairingCreatesAndUnlinksSupersetByContainment() throws {
        let app = launchWorkoutApp(fixture: .currentSession)

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        app.buttons["stage-queue-button"].tap()
        XCTAssertTrue(app.staticTexts["This Session"].waitForExistence(timeout: 3))

        // Creation is worded, not glyphed: `Pair` → `Pair with this` (DESIGN.md §5.4).
        tapWhenHittable(app.buttons["stage-queue-pair-exercise-0"])
        XCTAssertTrue(app.staticTexts["Pick a partner"].waitForExistence(timeout: 3))

        tapWhenHittable(app.buttons["stage-queue-pairwith-exercise-1"])

        // The formed Superset reads by containment: one group with a sentence-case
        // caption holding both Exercises.
        let supersetGroup = app.buttons["stage-queue-row-superset-0"]
        XCTAssertTrue(supersetGroup.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Superset"].exists)
        XCTAssertTrue(supersetGroup.staticTexts["Back Squat"].exists)
        XCTAssertTrue(supersetGroup.staticTexts["BB RDL"].exists)

        // Dissolution lives in the containment group as `Unlink`.
        tapWhenHittable(app.buttons["stage-queue-unlink-superset-0"])

        XCTAssertTrue(app.buttons["stage-queue-row-exercise-0"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["stage-queue-row-exercise-1"].exists)
        XCTAssertFalse(app.buttons["stage-queue-row-superset-0"].exists)
        XCTAssertTrue(app.buttons["stage-queue-pair-exercise-0"].exists)
    }

    @MainActor
    func testQueuePairingCanBeCancelled() throws {
        let app = launchWorkoutApp(fixture: .currentSession)

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        app.buttons["stage-queue-button"].tap()
        XCTAssertTrue(app.staticTexts["This Session"].waitForExistence(timeout: 3))

        tapWhenHittable(app.buttons["stage-queue-pair-exercise-0"])
        XCTAssertTrue(app.staticTexts["Pick a partner"].waitForExistence(timeout: 3))

        tapWhenHittable(app.buttons["stage-queue-cancel-pairing"])

        XCTAssertTrue(app.staticTexts["This Session"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["stage-queue-pair-exercise-0"].exists)
        XCTAssertFalse(app.buttons["stage-queue-row-superset-0"].exists)
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
        launchWorkoutApp(fixture: .currentSession)
    }
}
