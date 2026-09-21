import XCTest

final class WorkoutTrackerInteractionUITests: XCTestCase {
    @MainActor
    func testActiveSetFieldFocusDismissesWithoutCardCancel() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.buttons["Skip"].exists)

        app.buttons["weight-pill"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.appears(within: 3))

        tapActiveSetCardHeaderBackground(in: app)

        XCTAssertFalse(app.keyboards.firstMatch.appears(within: 1))
        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)

        XCTAssertTrue(app.buttons["log-active-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
    }

    @MainActor
    func testTapOnNonInteractiveStageContentDismissesKeyboard() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)

        app.buttons["weight-pill"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.appears(within: 3))

        tapEmptyStageSpaceBetweenBranchAndRunline(in: app)

        XCTAssertFalse(app.keyboards.firstMatch.appears(within: 1))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        waitForLabel("Weight, 237.5", on: app.buttons["weight-pill"])
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
    func testCompletionStageListsOpenExercisesAndNavigatesToSource() throws {
        let app = launchWorkoutApp(
            fixture: .completedSessionWithOpenExercises,
            options: [.disableCelebrationBloom]
        )

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
        XCTAssertTrue(picker.appears(within: 3))
        XCTAssertTrue(app.buttons["System"].exists)
        XCTAssertTrue(app.buttons["Light"].exists)
        XCTAssertTrue(app.buttons["Night"].exists)
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

        XCTAssertTrue(app.staticTexts["Choose your training sheet"].appears(within: 3))
        XCTAssertFalse(app.staticTexts["Back Squat"].exists)

        let replacementRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Replacement Training Log")
        ).firstMatch
        XCTAssertTrue(replacementRow.appears(within: 3))
        replacementRow.tap()

        XCTAssertTrue(app.staticTexts["Replacement Squat"].appears(within: 3))
        XCTAssertFalse(app.staticTexts["Back Squat"].exists)
    }

    /// Pins the identifier and the accessible name on the URL field. Without them VoiceOver reads a
    /// filled field back as its contents alone, and no recipe can target it without a coordinate.
    @MainActor
    func testPastedURLGoesThroughANamedFieldAndLandsOnTheSyncedSession() throws {
        let app = launchWorkoutApp(fixture: .onboarding, options: [.disableCelebrationBloom])

        XCTAssertTrue(app.staticTexts["Choose your training sheet"].appears(within: 3))
        tapWhenHittable(app.buttons["Paste a URL instead"])

        let field = app.textFields["onboarding-url-field"]
        XCTAssertTrue(field.appears(within: 3))
        XCTAssertEqual(field.label, "Google Sheet URL")

        field.tap()
        field.typeText("https://docs.google.com/spreadsheets/d/REPLACEMENT/edit")
        XCTAssertEqual(field.label, "Google Sheet URL")

        tapWhenHittable(app.buttons["Save"])

        XCTAssertTrue(app.staticTexts["Replacement Squat"].appears(within: 3))
    }
}

@MainActor
private func tapEmptyStageSpaceBetweenBranchAndRunline(in app: XCUIApplication) {
    let branchEnd = app.buttons["Set 3, 5 · RPE8"].frame.maxY
    let runlineStart = app.staticTexts["Block 26 · W4 D3 — 245x5@6, 255x5@7"].frame.minY
    app.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: app.frame.midX, dy: (branchEnd + runlineStart) / 2))
        .tap()
}

@MainActor
private func tapActiveSetCardHeaderBackground(in app: XCUIApplication) {
    let activeSetCard = app.otherElements["active-set-card"]
    XCTAssertTrue(activeSetCard.appears(within: 3))
    activeSetCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14)).tap()
}

final class WorkoutTrackerLongSessionUITests: XCTestCase {
    @MainActor
    func testLongSessionQueueListsEveryExerciseAndJumpLandsOnStage() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        let queueButton = app.buttons["stage-queue-button"]
        waitForLabel("1 of 8", on: queueButton)
        queueButton.tap()

        XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))
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

        XCTAssertTrue(app.staticTexts["Farmer Carry"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Tall posture."].exists)
    }

    @MainActor
    private func launchFixtureApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .longSession)
    }
}

final class WorkoutTrackerSupersetUITests: XCTestCase {
    @MainActor
    func testQueuePairingCanBeCancelled() throws {
        let app = launchWorkoutApp(fixture: .currentSession)

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        app.buttons["stage-queue-button"].tap()
        XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))

        tapWhenHittable(app.buttons["stage-queue-pair-exercise-0"])
        XCTAssertTrue(app.staticTexts["Pick a partner"].appears(within: 3))

        tapWhenHittable(app.buttons["stage-queue-cancel-pairing"])

        XCTAssertTrue(app.staticTexts["This Session"].appears(within: 3))
        XCTAssertTrue(app.buttons["stage-queue-pair-exercise-0"].exists)
        XCTAssertFalse(app.buttons["stage-queue-row-superset-0"].exists)
    }
}

final class WorkoutTrackerValueRailUITests: XCTestCase {
    @MainActor
    func testDraggingTheRepsTrackMovesRepsWhileRPEChipsOverhangIt() throws {
        let app = launchWorkoutApp(fixture: .currentSession)
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 237.5 × 5 @6", on: logButton)

        dragRail(in: app, bringing: "rpe-8", onto: "rpe-6")
        waitForLabel("Log 237.5 × 5 @8", on: logButton)

        let spilledRPEChip = app.buttons["rpe-6.5"]
        XCTAssertTrue(spilledRPEChip.appears(within: 3))
        let repsChipSpan = app.buttons["reps-5"].frame.midX...app.buttons["reps-6"].frame.midX
        XCTAssertTrue(
            repsChipSpan.contains(spilledRPEChip.frame.midX),
            "expected the RPE 6.5 chip to have spilled onto the Reps track, between two Reps chips"
        )

        dragRail(in: app, bringing: "reps-7", onto: "reps-5", startingOn: "rpe-6.5")
        waitForLabel("Log 237.5 × 7 @8", on: logButton)
    }
}

@MainActor
private func dragRail(
    in app: XCUIApplication,
    bringing targetChip: String,
    onto selectedChip: String,
    startingOn startChip: String? = nil
) {
    let target = app.buttons[targetChip]
    let selected = app.buttons[selectedChip]
    let start = app.buttons[startChip ?? selectedChip]
    XCTAssertTrue(target.appears(within: 3))
    XCTAssertTrue(selected.appears(within: 3))
    XCTAssertTrue(start.appears(within: 3))

    let travel = selected.frame.midX - target.frame.midX
    let from = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: travel, dy: 0)))
}

final class WorkoutTrackerSkipUITests: XCTestCase {
    @MainActor
    func testActiveSetCanBeSkippedWithHold() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let logButton = app.buttons["log-active-set-button"]
        waitUntilEnabled(logButton)

        logButton.press(forDuration: 1.0)

        XCTAssertTrue(app.buttons["Set 1, skip"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].appears(within: 3))
    }

    @MainActor
    private func launchFixtureApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .currentSession)
    }
}
