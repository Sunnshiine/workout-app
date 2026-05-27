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
    private func launchFixtureApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITEST_FIXTURE"]
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
        XCTAssertTrue(element.waitForExistence(timeout: 3))
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
}
