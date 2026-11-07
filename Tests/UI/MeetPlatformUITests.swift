import XCTest

final class MeetPlatformUITests: XCTestCase {
    /// A mark brings up Submit under the same thumb, so the taps that follow it must not reach Submit.
    @MainActor
    func testRapidTapsOnAMarkLeaveTheNextAttemptUnsubmitted() throws {
        let app = launchWorkoutApp(fixture: .meetDay)
        let noLift = reachTheMarks(app)

        noLift.tap(withNumberOfTaps: 3, numberOfTouches: 1)

        let submit = app.buttons["meet-submit"]
        XCTAssertTrue(submit.appears(within: uiEventBudget), "the first tap opens the window, and no later tap reaches Submit")

        waitPastTheHold()
        tapWhenHittable(submit)
        XCTAssertTrue(
            app.descendants(matching: .any)["meet-readout"].appears(within: uiEventBudget),
            "one tap after the hold should submit, so Submit was held off rather than covered"
        )
    }

    /// A slow press once landed a caret after the selection, so the digit went into the weight.
    @MainActor
    func testFirstDigitAfterASlowPressReplacesTheWeight() throws {
        let app = launchWorkoutApp(fixture: .meetDay)
        reachTheMarks(app).tap()

        let field = app.textFields["meet-weight-field"]
        XCTAssertTrue(field.appears(within: uiEventBudget))
        waitPastTheHold()
        field.press(forDuration: 1.2)
        XCTAssertTrue(app.keyboards.firstMatch.appears(within: uiEventBudget))
        app.typeText("1")
        XCTAssertEqual(field.value as? String, "1")
    }

    @MainActor
    @discardableResult
    private func reachTheMarks(_ app: XCUIApplication) -> XCUIElement {
        tapWhenHittable(app.buttons["block-overview-meet-row"])
        tapWhenHittable(app.buttons["meet-to-platform"])

        let fewer = app.buttons["meet-attempts-out-down"]
        XCTAssertTrue(fewer.appears(within: uiEventBudget))
        let noLift = app.buttons["meet-mark-no-lift"]
        while fewer.exists, !noLift.exists {
            fewer.tap()
        }
        waitPastTheHold()
        return noLift
    }

    /// A new stage holds off touches for 0.4 s, so a tap sooner than this is dropped by design.
    private func waitPastTheHold() {
        Thread.sleep(forTimeInterval: 0.6)
    }
}
