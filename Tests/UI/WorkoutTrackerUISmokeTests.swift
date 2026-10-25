import XCTest

private let dictateLink = URL(string: "workouttracker://dictate")!

/// Opens the dictate link in the app already running, which asks for what Log a Set asks with the app in front.
/// `XCUIApplication.open(_:)` relaunches the app instead, which drops whatever covered the stage.
@MainActor
private func openDictateLinkInTheRunningApp() {
    XCUIDevice.shared.system.open(dictateLink)
    let confirm = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
    if confirm.appears(within: 2) {
        confirm.tap()
    }
}

final class WorkoutTrackerUISmokeTests: XCTestCase {
    @MainActor
    func testCurrentSessionLogsFirstSetAndAdvancesActiveSet() throws {
        let app = launchCurrentSessionSmokeApp(options: [.offline])

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let hud = app.otherElements["session-header-hud"].frame
        let name = app.staticTexts["stage-exercise-name"].frame

        app.buttons["rpe-6"].tap()
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 237.5 × 5 @6", on: logButton)
        logButton.tap()

        XCTAssertTrue(app.buttons["Set 1, 237.5x5@6"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].appears(within: 3))

        let banner = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sync status:")).firstMatch
        XCTAssertTrue(banner.appears(within: 3))
        XCTAssertGreaterThanOrEqual(banner.frame.minY, hud.minY, "the banner starts at or below the HUD's top")
        XCTAssertEqual(app.otherElements["session-header-hud"].frame, hud, "the banner leaves the HUD where it was")
        XCTAssertEqual(app.staticTexts["stage-exercise-name"].frame, name, "the banner leaves the Exercise name where it was")

        app.buttons["session-location-button"].tap()
        XCTAssertTrue(app.navigationBars["Block 27"].appears(within: 3), "the runline under the banner still opens Block Overview")
    }

    @MainActor
    func testOffLiveEdgeControlsReturnToCurrentSession() throws {
        let app = launchCurrentSessionSmokeApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))

        app.buttons["session-location-button"].tap()
        XCTAssertTrue(app.navigationBars["Block 27"].appears(within: 3))

        app.otherElements["session-tile-W1-D3"].tap()
        waitForLabel("Open Block Overview for Week 1, Day 3", on: app.buttons["session-location-button"])
        XCTAssertTrue(app.buttons["go-back-current-session-button"].appears(within: 3))
        XCTAssertTrue(app.buttons["make-current-session-button"].exists)

        app.buttons["go-back-current-session-button"].tap()
        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        waitForLabel("Open Block Overview for Week 1, Day 1", on: app.buttons["session-location-button"])
    }

    @MainActor
    func testSettingsPendingWriteSignOutConfirmation() throws {
        let app = launchSettingsSmokeApp()

        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 3))
        let trainingSheetRow = app.buttons["settings-training-sheet-row"]
        XCTAssertTrue(trainingSheetRow.appears(within: 3))
        XCTAssertTrue(trainingSheetRow.label.contains("Fixture Training Log"))

        let confirmSignOut = app.buttons["sign-out-confirm-button"]
        app.buttons["settings-sign-out-button"].tap()
        XCTAssertTrue(app.staticTexts["You have unsynced changes. Sign out anyway?"].appears(within: 3))
        XCTAssertEqual(confirmSignOut.label, "Sign Out")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(confirmSignOut.appears(within: 1))

        app.buttons["settings-sign-out-button"].tap()
        XCTAssertTrue(confirmSignOut.appears(within: 3))
        confirmSignOut.tap()

        XCTAssertFalse(confirmSignOut.appears(within: 1))
        waitForLabel("Training Sheet, Google Sheet", on: trainingSheetRow)
    }

    @MainActor
    func testSayingASetLogsItAndHoldsItOnTheCardWithClearBeforeMovingOn() throws {
        let app = launchWorkoutApp(fixture: .currentSession, dictating: "235 for 5 at 7")
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].appears(within: 3))

        app.buttons["say-set-button"].press(forDuration: 1)

        XCTAssertTrue(app.buttons["Set 1, 235x5@7"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists, "the card holds the Set it just logged")
        XCTAssertTrue(app.staticTexts["Saved"].exists)
        XCTAssertTrue(app.buttons["clear-logged-set-menu"].exists)
        XCTAssertFalse(app.buttons["say-set-button"].exists)
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].appears(within: 8), "the hold ends and the card moves on")
        XCTAssertTrue(app.buttons["say-set-button"].exists)
    }

    @MainActor
    func testATouchOnTheHeldCardMovesOnWithoutChangingTheSetItWrote() throws {
        let app = launchWorkoutApp(fixture: .currentSession, dictating: "235 for 5 at 7")
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].appears(within: 3))
        app.buttons["say-set-button"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["clear-logged-set-menu"].appears(within: 3))
        XCTAssertFalse(app.buttons["rpe-7.5"].isEnabled, "the held Set's values take no edit")

        app.buttons["rpe-7.5"].tap()

        XCTAssertTrue(app.staticTexts["Set 2 of 3"].appears(within: 3))
        XCTAssertTrue(app.buttons["Set 1, 235x5@7"].exists, "the touch only moves the card on")
        XCTAssertTrue(app.staticTexts["Sync status: 1 unsynced"].exists)
    }

    @MainActor
    func testTheHeldSetWaitsWhileItsClearMenuIsOpenAndAClearUndoesTheWrite() throws {
        let app = launchWorkoutApp(fixture: .currentSession, dictating: "235 for 5 at 7")
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].appears(within: 3))
        app.buttons["say-set-button"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["clear-logged-set-menu"].appears(within: 3))

        app.buttons["clear-logged-set-menu"].tap()
        let clear = app.buttons["Clear"]
        XCTAssertTrue(clear.appears(within: 2))

        XCTAssertFalse(app.staticTexts["Set 2 of 3"].appears(within: 6), "the open menu keeps the card on the Set")
        XCTAssertTrue(clear.exists, "the hold left the menu open")
        clear.tap()

        XCTAssertTrue(app.buttons["Set 1, 5 · RPE6"].appears(within: 3), "the Clear undid the write")
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        XCTAssertTrue(app.buttons["say-set-button"].exists)
    }

    @MainActor
    func testClosingTheHeldSetsClearMenuWithoutAClearMovesTheCardOn() throws {
        let app = launchWorkoutApp(fixture: .currentSession, dictating: "235 for 5 at 7")
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].appears(within: 3))
        app.buttons["say-set-button"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["clear-logged-set-menu"].appears(within: 3))
        app.buttons["clear-logged-set-menu"].tap()
        XCTAssertTrue(app.buttons["Clear"].appears(within: 2))
        XCTAssertFalse(app.staticTexts["Set 2 of 3"].appears(within: 5), "the open menu keeps the card on the Set")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()

        XCTAssertTrue(app.staticTexts["Set 2 of 3"].appears(within: 3), "closing the menu moves the card on")
        XCTAssertTrue(app.buttons["Set 1, 235x5@7"].exists)
    }

    @MainActor
    func testASpokenSetThatDoesNotReadWritesNothingAndShowsWhatWasHeard() throws {
        let app = launchWorkoutApp(fixture: .currentSession, dictating: "100 kilos for 5")
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].appears(within: 3))

        app.buttons["say-set-button"].press(forDuration: 1)

        let heard = app.descendants(matching: .any)["spoken-set-capsule"]
        waitForLabel("“100 kilos for 5”", on: heard)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let banner = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sync status:")).firstMatch
        XCTAssertFalse(banner.appears(within: 1), "nothing was queued for the Sheet")

        heard.tap()

        waitForLabel("Log 237.5 × 5 @6", on: app.buttons["log-active-set-button"])
    }

    @MainActor
    func testTheDictateLinkLogsTheActiveSetWithNoTouchOnTheMic() throws {
        let app = launchWorkoutApp(fixture: .currentSession, dictating: "235 for 5 at 7")
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].appears(within: 3))

        app.open(dictateLink)

        XCTAssertTrue(app.buttons["Set 1, 235x5@7"].appears(within: 6), "the Set logs once the athlete stops talking")
        XCTAssertTrue(app.staticTexts["Saved"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists, "the card holds the Set it just logged")
    }

    @MainActor
    func testTheDictateLinkClosesSettingsAndTheBlockGridAndLogsOnTheCurrentSession() throws {
        let app = launchWorkoutApp(fixture: .currentSession, dictating: "235 for 5 at 7")
        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        app.buttons["session-location-button"].tap()
        app.otherElements["session-tile-W1-D3"].tap()
        waitForLabel("Open Block Overview for Week 1, Day 3", on: app.buttons["session-location-button"])
        app.buttons["session-location-button"].tap()
        tapWhenHittable(app.buttons["block-overview-settings-row"])
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 3))

        openDictateLinkInTheRunningApp()

        XCTAssertTrue(app.buttons["Set 1, 235x5@7"].appears(within: 8), "the Current Session's first Set logs")
        XCTAssertFalse(app.navigationBars["Settings"].exists)
        XCTAssertFalse(app.navigationBars["Block 27"].exists)
        waitForLabel("Open Block Overview for Week 1, Day 1", on: app.buttons["session-location-button"])
    }

    @MainActor
    func testTheDictateLinkWithNothingToLogLeavesSettingsAndTheBlockGridOpen() throws {
        let app = launchWorkoutApp(fixture: .completedSessionWithOpenExercises, dictating: "235 for 5 at 7")
        XCTAssertTrue(app.staticTexts["Session complete"].appears(within: 3))
        app.buttons["session-location-button"].tap()
        tapWhenHittable(app.buttons["block-overview-settings-row"])
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 3))

        openDictateLinkInTheRunningApp()

        XCTAssertFalse(app.staticTexts["Session complete"].appears(within: 3), "a request with nothing to log closes nothing")
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    @MainActor
    func testTheDictateLinkOnOnboardingEndsThereSoChoosingASheetLogsNothing() throws {
        let app = launchWorkoutApp(fixture: .onboarding, dictating: "235 for 5 at 7")
        XCTAssertTrue(app.staticTexts["Choose your training sheet"].appears(within: 3))

        app.open(dictateLink)
        let replacementRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Replacement Training Log")).firstMatch
        XCTAssertTrue(replacementRow.appears(within: 3))
        replacementRow.tap()

        XCTAssertTrue(app.staticTexts["Replacement Squat"].appears(within: 3))
        XCTAssertFalse(app.staticTexts["Session complete"].appears(within: 5), "the request onboarding met never logs the Set")
        XCTAssertEqual(app.staticTexts["session-remaining-count"].label, "1 Set left")
        XCTAssertFalse(app.staticTexts["Saved"].exists)
    }

    @MainActor
    func testTheDictateLinkWhileTheSignInRestoresLogsTheSetOnceTheRestoreSignsIn() throws {
        let app = launchWorkoutApp(fixture: .currentSession, options: [.lateSignIn], dictating: "235 for 5 at 7")
        XCTAssertTrue(app.buttons["onboarding-connect-button"].appears(within: 3))

        app.open(dictateLink)

        XCTAssertTrue(app.buttons["onboarding-connect-button"].appears(within: 2), "the link lands while the sign-in restores")
        XCTAssertTrue(app.buttons["Set 1, 235x5@7"].appears(within: 10), "the Set logs once the restore signs the athlete in")
        XCTAssertTrue(app.staticTexts["Saved"].exists)
    }

    @MainActor
    private func launchCurrentSessionSmokeApp(options: [WorkoutUITestFixtureOption] = []) -> XCUIApplication {
        launchWorkoutApp(fixture: .currentSession, options: options)
    }

    @MainActor
    private func launchSettingsSmokeApp() -> XCUIApplication {
        launchWorkoutApp(
            fixture: .settings,
            options: [.pendingWrite]
        )
    }
}
