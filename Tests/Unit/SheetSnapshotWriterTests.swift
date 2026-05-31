import Testing

@testable import WorkoutTracker

private func snapshotWriterGrid(_ cells: [String: String]) -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes"
        ].merging(cells) { _, new in new },
        rows: 30,
        cols: 30
    )
}

@Test func skipsUserHiddenContinuationRowWhenPlanningSetLogWrite() throws {
    let grid = snapshotWriterGrid(["C15": "Squat", "D15": "1", "K15": "Coach note", "C18": "Bench"])
    let snapshot = SheetSnapshot(
        values: grid,
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )
    let planner = SheetWritePlanner()

    let update = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Squat",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "185x5@8",
            expectedCurrentValue: ""
        ),
        in: planner.snapshot(for: snapshot)
    )

    #expect(update.range == "'Block 27'!K17")
}

@Test func skipsFilterHiddenContinuationRowWhenPlanningSetLogWrite() throws {
    let grid = snapshotWriterGrid(["C15": "Squat", "D15": "1", "K15": "Coach note", "C18": "Bench"])
    let snapshot = SheetSnapshot(
        values: grid,
        rowVisibility: [15: SheetRowVisibility(hiddenByFilter: true)]
    )
    let planner = SheetWritePlanner()

    let update = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Squat",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "185x5@8",
            expectedCurrentValue: ""
        ),
        in: planner.snapshot(for: snapshot)
    )

    #expect(update.range == "'Block 27'!K17")
}

@Test func rowsWithoutVisibilityMetadataRemainWritable() throws {
    let grid = snapshotWriterGrid(["C15": "Squat", "D15": "1", "K15": "Coach note", "C18": "Bench"])
    let planner = SheetWritePlanner()

    let update = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Squat",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "185x5@8",
            expectedCurrentValue: ""
        ),
        in: planner.snapshot(for: SheetSnapshot(values: grid))
    )

    #expect(update.range == "'Block 27'!K16")
}
