import Testing

@testable import WorkoutTracker

/// Week 2 of Block 31: the coach hid a movement under Leg Ext., whose header Notes hold a Coach
/// Note. Row 49 is the only visible row left before Preacher Curl.
private func legExtensionPlan(_ cells: [String: String] = [:]) throws -> SheetCellWrite {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "K14": "Notes",
            "C46": "0:2:0 Leg Ext.", "D46": "2", "F46": "9 - 10",
            "K46": "Start w/ 15 sec hold at the top, and then proceed into leg ext. at prescribed cadence",
            "C47": "0:2:0 Sissy Squat", "D47": "2", "K48": "100x10@8",
            "C50": "0:2:0 Preacher Curl", "D50": "2"
        ].merging(cells) { _, new in new },
        rows: 60,
        cols: 30
    )
    let planner = SheetWritePlanner()
    let hidden = SheetRowVisibility(hiddenByUser: true)
    let snapshot = planner.snapshot(for: SheetSnapshot(values: grid, rowVisibility: [46: hidden, 47: hidden]))
    let request = SheetWriteRequest(
        session: SessionCoordinate(blockTab: "Block - 31", address: SessionAddress(week: 1, day: 1)),
        exerciseName: "0:2:0 Leg Ext.",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "105x9@9",
        expectedCurrentValue: ""
    )
    return try planner.plan(request, in: snapshot)
}

@Test func writesPastAHiddenExerciseToTheVisibleRowBeforeTheNextExercise() throws {
    #expect(try legExtensionPlan() == SheetCellWrite(tabName: "Block - 31", a1: "K49", value: "105x9@9"))
}

@Test func leavesAHiddenExercisesVisibleLogRowToIt() {
    #expect(throws: SheetWriterError.headerNotesBlockSetRow(exercise: .first("0:2:0 Leg Ext."), setIndex: 0)) {
        try legExtensionPlan(["K49": "95x10@8"])
    }
}
