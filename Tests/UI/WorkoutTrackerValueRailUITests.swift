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

    /// A drag that yields to the vertical axis is still a drag, so the cell under the lifted finger
    /// does not fire (DESIGN.md §9, Intent Before Direction).
    @MainActor
    func testAVerticalDragOnACellLeavesTheSelectionAlone() throws {
        let app = launchWorkoutApp(fixture: .currentSession)
        let logButton = app.buttons["log-active-set-button"]
        waitForLabel("Log 237.5 × 5 @6", on: logButton)
        let cell = app.buttons["reps-6"]
        XCTAssertTrue(cell.appears(within: 3))

        let from = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 14)), withVelocity: .slow, thenHoldForDuration: 0.3)

        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(logButton.label, "Log 237.5 × 5 @6")
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

    // The strip follows the finger 1:1 and a release throws it by its speed, so the drag is slow and
    // the finger rests before it lifts, landing the target cell under the centre.
    let travel = selected.frame.midX - target.frame.midX
    let from = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    from.press(
        forDuration: 0.1,
        thenDragTo: from.withOffset(CGVector(dx: travel, dy: 0)),
        withVelocity: .slow,
        thenHoldForDuration: 0.3
    )
}
