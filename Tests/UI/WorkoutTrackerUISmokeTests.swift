import XCTest

final class WorkoutTrackerUISmokeTests: XCTestCase {
    @MainActor
    func testCurrentSessionLogsFirstSetAndAdvancesActiveSet() throws {
        let app = launchCurrentSessionSmokeApp()

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

        app.buttons["rpe-7.5"].tap()

        XCTAssertTrue(app.staticTexts["Set 2 of 3"].appears(within: 3))
        XCTAssertTrue(app.buttons["Set 1, 235x5@7"].exists, "the touch only moves the card on")
        XCTAssertTrue(app.staticTexts["Sync status: 1 unsynced"].exists)
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
    private func launchCurrentSessionSmokeApp() -> XCUIApplication {
        launchWorkoutApp(fixture: .currentSession)
    }

    @MainActor
    private func launchSettingsSmokeApp() -> XCUIApplication {
        launchWorkoutApp(
            fixture: .settings,
            options: [.pendingWrite]
        )
    }
}
