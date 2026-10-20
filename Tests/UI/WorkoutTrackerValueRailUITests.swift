import XCTest

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
