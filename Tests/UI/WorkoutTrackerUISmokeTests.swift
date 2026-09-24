import XCTest

final class WorkoutTrackerUISmokeTests: XCTestCase {
    @MainActor
    func testCurrentSessionLogsFirstSetAndAdvancesActiveSet() throws {
        let app = launchCurrentSessionSmokeApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)
        let safeTop = app.otherElements["session-header-hud"].frame.minY

        app.buttons["rpe-6"].tap()
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 237.5 × 5 @6", on: logButton)
        logButton.tap()

        XCTAssertTrue(app.buttons["Set 1, 237.5x5@6"].appears(within: 3))
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].appears(within: 3))

        let banner = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sync status:")).firstMatch
        XCTAssertTrue(banner.appears(within: 3))
        XCTAssertGreaterThanOrEqual(banner.frame.minY, safeTop, "the banner starts at or below the safe top, where the HUD started")
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

        app.buttons["settings-sign-out-button"].tap()
        XCTAssertTrue(app.alerts["You have unsynced changes. Sign out anyway?"].appears(within: 3))
        app.alerts.buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 3))
        app.buttons["settings-sign-out-button"].tap()
        XCTAssertTrue(app.alerts["You have unsynced changes. Sign out anyway?"].appears(within: 3))
        app.alerts.buttons["Sign Out"].tap()

        XCTAssertFalse(app.alerts["You have unsynced changes. Sign out anyway?"].appears(within: 1))
    }

    @MainActor
    private func launchCurrentSessionSmokeApp() -> XCUIApplication {
        launchWorkoutApp(
            fixture: .currentSession,
            options: [.disableCelebrationBloom]
        )
    }

    @MainActor
    private func launchSettingsSmokeApp() -> XCUIApplication {
        launchWorkoutApp(
            fixture: .settings,
            options: [.pendingWrite]
        )
    }
}
