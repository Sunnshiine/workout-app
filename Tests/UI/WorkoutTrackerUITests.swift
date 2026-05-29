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
        XCTAssertTrue(app.buttons["back-to-current-session-button"].exists)

        app.buttons["back-to-current-session-button"].tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOverscrollToolbarRevealsSettingsAndSyncControls() throws {
        let app = launchFixtureApp()

        XCTAssertTrue(app.staticTexts["Back Squat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["session-toolbar-settings-button"].exists)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            )

        let settingsButton = app.buttons["session-toolbar-settings-button"]
        let syncButton = app.buttons["session-toolbar-sync-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        XCTAssertTrue(syncButton.exists)

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
        XCTAssertTrue(syncButton.waitForExistence(timeout: 3))
        syncButton.tap()
        XCTAssertTrue(app.staticTexts["Offline"].waitForExistence(timeout: 3))

        app.swipeUp()
        XCTAssertFalse(settingsButton.waitForExistence(timeout: 1))
    }

    @MainActor
    func testOpenExerciseMakeupFlowShowsLastPerformedAndLogsSet() throws {
        let app = launchFixtureApp(extraArguments: ["-UITEST_OPEN_EXERCISES"])

        app.swipeUp()
        let openBackSquat = app.buttons.containing(.staticText, identifier: "Back Squat").firstMatch
        tapWhenHittable(openBackSquat)

        XCTAssertTrue(app.buttons["back-to-current-session-button"].waitForExistence(timeout: 3))
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

        app.buttons["session-toolbar-settings-button"].tap()
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

        app.buttons["session-toolbar-settings-button"].tap()
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

        app.buttons["session-toolbar-settings-button"].tap()
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
        app.launchArguments = ["-UITEST_FIXTURE"] + extraArguments
        app.launch()
        return app
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
        let approvedQuotes = [
            "You're fucking amazing.",
            "God damn!",
            "Get it girl!",
            "Shake it!"
        ]
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

        for element in [quote, title, subline, hint] + stats {
            XCTAssertTrue(element.waitForExistence(timeout: 3))
            XCTAssertTrue(windowFrame.contains(element.frame), "\(element) is clipped outside \(windowFrame)")
        }

        XCTAssertLessThanOrEqual(quote.frame.maxY, title.frame.minY)
        XCTAssertLessThanOrEqual(title.frame.maxY, subline.frame.minY)
        XCTAssertLessThan(stats.map(\.frame.maxY).max() ?? 0, hint.frame.minY)
    }
}
