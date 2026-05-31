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

@Test func aggregatesProtectedHeaderSetLogsInFirstVisibleWritableRow() throws {
    let grid = snapshotWriterGrid(["C15": "Squat", "D15": "2", "K15": "Coach note", "C19": "Bench"])
    let snapshot = SheetSnapshot(
        values: grid,
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )
    let planner = SheetWritePlanner()
    let planningSnapshot = planner.snapshot(for: snapshot)

    let setOneUpdate = try planner.plan(
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
        in: planningSnapshot
    )
    let updatedSnapshot = planner.applying(setOneUpdate, to: planningSnapshot)
    let setTwoUpdate = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Squat",
            setIndex: 1,
            column: .notes,
            operation: .upsert,
            valueToWrite: "195x5@9",
            expectedCurrentValue: ""
        ),
        in: updatedSnapshot
    )

    #expect(setOneUpdate.range == "'Block 27'!K17")
    #expect(setOneUpdate.value == "185x5@8")
    #expect(setTwoUpdate.range == "'Block 27'!K17")
    #expect(setTwoUpdate.value == "185x5@8, 195x5@9")
}

@Test func protectedHeaderAggregateConflictsOnUnexpectedSelectedTargetContent() throws {
    let grid = snapshotWriterGrid(["C15": "Squat", "D15": "2", "K15": "Coach note", "K16": "coach edited"])
    let planner = SheetWritePlanner()

    do {
        _ = try planner.plan(
            SheetWriteRequest(
                blockTab: "Block 27",
                week: 1,
                day: 1,
                exerciseName: "Squat",
                setIndex: 1,
                column: .notes,
                operation: .upsert,
                valueToWrite: "195x5@9",
                expectedCurrentValue: ""
            ),
            in: planner.snapshot(for: SheetSnapshot(values: grid))
        )
        Issue.record("Expected unexpected content in selected target to conflict")
    } catch let error as SheetWriterError {
        #expect(error == .unexpectedCurrentValue(expected: "", actual: "coach edited"))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
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

@Test func lastExerciseMayUseVisibleWritableRowBeforeNextWeek() throws {
    let grid = snapshotWriterGrid(
        [
            "C20": "Lateral Neck Flexion", "D20": "2", "K20": "Start light",
            "C23": "Day 1", "D25": "Sets", "K25": "Notes"
        ]
    )
    let planner = SheetWritePlanner()
    let planningSnapshot = planner.snapshot(for: SheetSnapshot(values: grid))

    let setOneUpdate = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Lateral Neck Flexion",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "BWx12@7",
            expectedCurrentValue: ""
        ),
        in: planningSnapshot
    )
    let updatedSnapshot = planner.applying(setOneUpdate, to: planningSnapshot)
    let setTwoUpdate = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Lateral Neck Flexion",
            setIndex: 1,
            column: .notes,
            operation: .upsert,
            valueToWrite: "BWx12@8",
            expectedCurrentValue: ""
        ),
        in: updatedSnapshot
    )

    #expect(setOneUpdate.range == "'Block 27'!K21")
    #expect(setTwoUpdate.range == "'Block 27'!K21")
    #expect(setTwoUpdate.value == "BWx12@7, BWx12@8")
}

@Test func lastExerciseDoesNotUseNextWeekRowAsVisibleWritableTarget() throws {
    let grid = snapshotWriterGrid(
        [
            "C20": "Lateral Neck Flexion", "D20": "1", "K20": "Start light",
            "C21": "Day 1", "D23": "Sets", "K23": "Notes"
        ]
    )
    let planner = SheetWritePlanner()

    do {
        _ = try planner.plan(
            SheetWriteRequest(
                blockTab: "Block 27",
                week: 1,
                day: 1,
                exerciseName: "Lateral Neck Flexion",
                setIndex: 0,
                column: .notes,
                operation: .upsert,
                valueToWrite: "BWx12@7",
                expectedCurrentValue: ""
            ),
            in: planner.snapshot(for: SheetSnapshot(values: grid))
        )
        Issue.record("Expected next Week boundary to block Set Log target selection")
    } catch let error as SheetWriterError {
        #expect(error == .headerNotesBlockSetRow(exerciseName: "Lateral Neck Flexion", setIndex: 0))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
}
