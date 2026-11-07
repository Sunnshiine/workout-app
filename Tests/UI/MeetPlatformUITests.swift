import XCTest

final class MeetPlatformUITests: XCTestCase {
    /// A mark brings up Submit under the same thumb, so the taps that follow it must not reach Submit.
    @MainActor
    func testRapidTapsOnAMarkLeaveTheNextAttemptUnsubmitted() throws {
        let app = launchWorkoutApp(fixture: .meetDay)
        tapWhenHittable(app.buttons["block-overview-meet-row"])
        tapWhenHittable(app.buttons["meet-to-platform"])

        let fewer = app.buttons["meet-attempts-out-down"]
        XCTAssertTrue(fewer.appears(within: uiEventBudget))
        let noLift = app.buttons["meet-mark-no-lift"]
        while fewer.exists, !noLift.exists {
            fewer.tap()
        }
        // Past the hold on the count's own last tap, so the first of these taps is the one that lands.
        Thread.sleep(forTimeInterval: 0.6)

        noLift.tap(withNumberOfTaps: 3, numberOfTouches: 1)

        let submit = app.buttons["meet-submit"]
        XCTAssertTrue(submit.appears(within: uiEventBudget), "the first tap opens the window, and no later tap reaches Submit")

        tapWhenHittable(submit)
        XCTAssertTrue(
            app.descendants(matching: .any)["meet-readout"].appears(within: uiEventBudget),
            "one tap after the hold should submit, so Submit was held off rather than covered"
        )
    }
}
