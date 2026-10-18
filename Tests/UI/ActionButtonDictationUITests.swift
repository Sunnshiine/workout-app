import XCTest

/// The Action button pressed with the app in the background and in front. Only a simulator whose
/// Action button was set to the Log a Set shortcut (Settings, Action Button, Shortcut, Choose a
/// Shortcut, WorkoutTracker) runs these, and `TEST_RUNNER_WORKOUT_ACTION_BUTTON=1` in the
/// xcodebuild environment says it was; without that they skip, so CI never presses a button set
/// to nothing.
final class ActionButtonDictationUITests: XCTestCase {
    @MainActor
    func testActionButtonLogsTheActiveSetOnTheLockScreenWithoutBringingTheAppForward() throws {
        let app = try launchForTheActionButton()

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        Self.pressLockButton()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCUIDevice.shared.press(.action)

        // Listening takes about 1.2 s and the readback follows the write; the app stays behind.
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        XCTAssertEqual(app.state, .runningBackground, "the Set logs without the app coming forward")

        // Wake, then Home unlocks a simulator with no passcode.
        Self.pressLockButton()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Set 1, 235x5@7"].appears(within: 5), "the headless Dictation logged the active Set")
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].appears(within: 3), "the card moved on to the next Set")
        XCTAssertTrue(app.otherElements["rest-pill"].appears(within: 3), "the stage shows the rest the locked log started")
        XCTAssertTrue(app.staticTexts["Sync status: 1 unsynced"].exists, "the write waits for the Sheet")
    }

    /// The readback names the Exercise that took the write, not the one the rest leads to.
    @MainActor
    func testActionButtonOnAnExercisesLastSetLogsThatSetWithTheAppBehind() throws {
        let app = try launchForTheActionButton()
        for _ in 0..<2 {
            app.buttons["log-active-set-button"].tap()
        }
        XCTAssertTrue(app.staticTexts["Set 3 of 3"].appears(within: 5), "the card reached the Exercise's last Set")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        Self.pressLockButton()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCUIDevice.shared.press(.action)
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        XCTAssertEqual(app.state, .runningBackground, "the Set logs without the app coming forward")

        Self.pressLockButton()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Set 1 of 2"].appears(within: 5), "the card moved past Back Squat's last Set to BB RDL")
        XCTAssertTrue(app.staticTexts["Sync status: 4 unsynced"].exists, "two card logs, and the last Set with its Last Set RPE")
    }

    /// The presses log Back Squat's last Set and both of BB RDL's. The rest the second press raised
    /// led to the Session's last Set, so the third press's readback leaves that rest rather than
    /// read "Next:" toward the Set it just wrote.
    @MainActor
    func testActionButtonOnTheSessionsLastSetLogsItWithTheAppBehind() throws {
        let app = try launchForTheActionButton()
        for _ in 0..<2 {
            app.buttons["log-active-set-button"].tap()
        }
        XCTAssertTrue(app.staticTexts["Set 3 of 3"].appears(within: 5), "the card reached Back Squat's last Set")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        Self.pressLockButton()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        for _ in 0..<3 {
            XCUIDevice.shared.press(.action)
            RunLoop.current.run(until: Date().addingTimeInterval(7))
        }
        XCTAssertEqual(app.state, .runningBackground, "the Sets log without the app coming forward")

        Self.pressLockButton()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCUIDevice.shared.press(.home)
        app.activate()
        let status = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sync status:'")).firstMatch
        XCTAssertTrue(status.appears(within: 5))
        XCTAssertEqual(status.label, "Sync status: 7 unsynced", "two card logs, three spoken Sets, and each Exercise's Last Set RPE")
    }

    @MainActor
    func testActionButtonWithTheAppInFrontListensOnTheCard() throws {
        let app = try launchForTheActionButton()

        XCUIDevice.shared.press(.action)

        XCTAssertTrue(app.buttons["Set 1, 235x5@7"].appears(within: 6), "the card logged the Set, not the headless path")
        XCTAssertTrue(app.staticTexts["Saved"].exists)
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].exists, "the card holds the Set it just logged")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    private func launchForTheActionButton() throws -> XCUIApplication {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["WORKOUT_ACTION_BUTTON"] == "1",
            "set the Action button to Log a Set, then run with TEST_RUNNER_WORKOUT_ACTION_BUTTON=1"
        )
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments =
            WorkoutUITestFixture.currentSession.launchArguments
            + ["-UITEST_DISABLE_ANIMATIONS", "-UITEST_DICTATION", "235 for 5 at 7"]
        app.launch()
        XCTAssertTrue(app.buttons["log-active-set-button"].appears(within: 10))
        XCTAssertFalse(app.buttons["Set 1, 235x5@7"].exists)
        return app
    }

    /// `XCUIDevice.ButtonType` has no lock button; the selector XCUIDevice has answered since
    /// Xcode 8 locks the screen the way `axe button lock` does, so the readback lands on the
    /// Lock Screen rather than behind the Home Screen.
    private static func pressLockButton() {
        let lock = Selector(("pressLockButton"))
        guard XCUIDevice.shared.responds(to: lock) else { return }
        XCUIDevice.shared.perform(lock)
    }
}
