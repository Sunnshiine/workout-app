import XCTest

final class WorkoutTrackerUISmokeTests: XCTestCase {
    @MainActor
    func testCurrentSessionLogsFirstSetAndAdvancesActiveSet() throws {
        let app = launchCurrentSessionSmokeApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists)

        app.buttons["rpe-6"].tap()
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 237.5×5@6", on: logButton)
        logButton.tap()

        XCTAssertTrue(app.buttons["Set 1, 237.5x5@6"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testMoveOnAdvancesToNextExercise() throws {
        let app = launchCurrentSessionSmokeApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        app.buttons["rpe-6"].tap()
        let logButton = app.buttons["log-active-set-button"]
        waitUntilEnabled(logButton)
        logButton.tap()

        waitForLabel("Weight, 252.5", on: app.buttons["weight-pill"])

        tapWhenReady(app.buttons["move-on-button"], in: app)
        let celebration = moveOnCelebration(in: app)
        XCTAssertTrue(celebration.waitForExistence(timeout: 3))
        waitForLabel("Week 1, Day 1", on: celebration)

        celebration.tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCurrentSessionOverrideControlsReturnToCurrentSession() throws {
        let app = launchCurrentSessionSmokeApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))

        app.buttons["session-location-button"].tap()
        XCTAssertTrue(app.navigationBars["Block 27"].waitForExistence(timeout: 3))

        app.buttons["Week 1, Day 3"].tap()
        waitForLabel("Open Block Overview for Week 1, Day 3", on: app.buttons["session-location-button"])
        XCTAssertTrue(app.buttons["go-back-current-session-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["make-current-session-button"].exists)

        app.buttons["go-back-current-session-button"].tap()
        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 3))
        waitForLabel("Open Block Overview for Week 1, Day 1", on: app.buttons["session-location-button"])
    }

    @MainActor
    func testSettingsPendingWriteSignOutConfirmation() throws {
        let app = launchSettingsSmokeApp()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Fixture Training Log"].exists)

        app.buttons["settings-sign-out-button"].tap()
        XCTAssertTrue(app.alerts["You have unsynced changes. Sign out anyway?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["settings-sign-out-button"].tap()
        XCTAssertTrue(app.alerts["You have unsynced changes. Sign out anyway?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Sign Out"].tap()

        XCTAssertFalse(app.alerts["You have unsynced changes. Sign out anyway?"].waitForExistence(timeout: 3))
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
