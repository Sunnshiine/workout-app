import Testing

@testable import WorkoutTracker

@Test func parserAndWriterAgreeOnCompactEmptyHeaderSetOne() throws {
    let grid = compactLayoutGrid(
        headerNotes: "",
        continuationNotes: "BWx10@8"
    )

    let exercise = try compactParsedExercise(from: grid)
    #expect(exercise.coachNote == nil)
    #expect(exercise.legacyLog == nil)
    #expect(exercise.sets[0].state == .pending)
    #expect(exercise.sets[0].setLog == nil)
    #expect(exercise.sets[1].state == .pending)
    #expect(exercise.sets[1].setLog == nil)

    let setOneUpdate = try SheetWritePlanner().plan(
        compactWriteRequest(setIndex: 0, valueToWrite: "BWx12@7", expectedCurrentValue: ""),
        in: grid
    )
    let setTwoUpdate = try SheetWritePlanner().plan(
        compactWriteRequest(setIndex: 1, valueToWrite: "BWx11@8", expectedCurrentValue: ""),
        in: grid
    )

    #expect(setOneUpdate.range == "'Block 27'!E18")
    #expect(setTwoUpdate.range == "'Block 27'!E18")
    #expect(setTwoUpdate.value == ", BWx11@8")
}

@Test func parserAndWriterAgreeOnCompactHeaderAggregateSetLogs() throws {
    let grid = compactLayoutGrid(
        headerNotes: "BWx12@7, BWx10@8",
        continuationNotes: ""
    )

    let exercise = try compactParsedExercise(from: grid)
    #expect(exercise.coachNote == nil)
    #expect(exercise.legacyLog == nil)
    #expect(exercise.sets.map { $0.setLog?.formatted } == ["BWx12@7", "BWx10@8"])

    let update = try SheetWritePlanner().plan(
        compactWriteRequest(setIndex: 1, valueToWrite: "BWx11@8", expectedCurrentValue: "BWx10@8"),
        in: grid
    )

    #expect(update.range == "'Block 27'!E18")
    #expect(update.value == "BWx12@7, BWx11@8")
}

@Test func parserAndWriterAgreeOnCompactHeaderSkipMarker() throws {
    let grid = compactLayoutGrid(
        headerNotes: "skip",
        continuationNotes: "BWx10@8"
    )

    let exercise = try compactParsedExercise(from: grid)
    #expect(exercise.coachNote == nil)
    #expect(exercise.legacyLog == nil)
    #expect(exercise.sets[0].state == .skipped)
    #expect(exercise.sets[0].setLog == nil)
    #expect(exercise.sets[1].state == .pending)
    #expect(exercise.sets[1].setLog == nil)

    let setOneUpdate = try SheetWritePlanner().plan(
        compactWriteRequest(setIndex: 0, valueToWrite: "BWx12@7", expectedCurrentValue: "skip"),
        in: grid
    )

    #expect(setOneUpdate.range == "'Block 27'!E18")
}

@Test func writerKeepsExerciseRowTargetWhenContinuationRowHasStaleLog() throws {
    let grid = compactLayoutGrid(
        headerNotes: "BWx12@7",
        continuationNotes: "BWx10@8"
    )

    let setTwoUpdate = try SheetWritePlanner().plan(
        compactWriteRequest(setIndex: 1, valueToWrite: "BWx11@8", expectedCurrentValue: ""),
        in: grid
    )

    #expect(setTwoUpdate.range == "'Block 27'!E18")
    #expect(setTwoUpdate.value == "BWx12@7, BWx11@8")
}

@Test func expectedCurrentValueChecksExerciseRowListEntry() throws {
    let grid = compactLayoutGrid(
        headerNotes: "BWx12@7",
        continuationNotes: "BWx10@8"
    )

    do {
        _ = try SheetWritePlanner().plan(
            compactWriteRequest(setIndex: 1, valueToWrite: "BWx11@8", expectedCurrentValue: "BWx10@8"),
            in: grid
        )
        Issue.record("Expected stale continuation-row value to be ignored")
    } catch let error as SheetWriterError {
        #expect(error == .unexpectedCurrentValue(expected: "BWx10@8", actual: ""))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
}

@Test func writerDeletesSetLogInsideExerciseRowList() throws {
    let grid = compactLayoutGrid(
        headerNotes: "BWx12@7, BWx10@8",
        continuationNotes: ""
    )

    let update = try SheetWritePlanner().plan(
        compactDeleteRequest(setIndex: 1, expectedCurrentValue: "BWx10@8"),
        in: grid
    )

    #expect(update.range == "'Block 27'!E18")
    #expect(update.value == "BWx12@7")
}

@Test func writerSkipsSetInsideExerciseRowList() throws {
    let grid = compactLayoutGrid(
        headerNotes: "BWx12@7, BWx10@8",
        continuationNotes: ""
    )

    let update = try SheetWritePlanner().plan(
        compactWriteRequest(setIndex: 1, valueToWrite: "skip", expectedCurrentValue: "BWx10@8"),
        in: grid
    )

    #expect(update.range == "'Block 27'!E18")
    #expect(update.value == "BWx12@7, skip")
}

private func compactLayoutGrid(headerNotes: String, continuationNotes: String) -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "E14": "Notes",
            "C18": "Ab of Choice", "D18": "2", "E18": headerNotes,
            "E19": continuationNotes,
            "C20": "Bench Press", "D20": "1"
        ],
        rows: 32,
        cols: 30
    )
}

private func compactParsedExercise(from grid: SheetGrid) throws -> ParsedExercise {
    let parsed = SheetParser().parse(grid: grid, tabName: "Block 27")
    return try #require(parsed.block.weeks.first?.days.first?.exercises.first)
}

private func compactWriteRequest(
    setIndex: Int,
    valueToWrite: String,
    expectedCurrentValue: String
) -> SheetWriteRequest {
    SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Ab of Choice",
        setIndex: setIndex,
        column: .notes,
        operation: .upsert,
        valueToWrite: valueToWrite,
        expectedCurrentValue: expectedCurrentValue
    )
}

private func compactDeleteRequest(
    setIndex: Int,
    expectedCurrentValue: String
) -> SheetWriteRequest {
    SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Ab of Choice",
        setIndex: setIndex,
        column: .notes,
        operation: .delete,
        valueToWrite: nil,
        expectedCurrentValue: expectedCurrentValue
    )
}
