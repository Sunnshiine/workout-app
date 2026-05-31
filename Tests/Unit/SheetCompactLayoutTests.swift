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
    #expect(exercise.sets[1].setLog?.formatted == "BWx10@8")

    let setOneUpdate = try SheetWritePlanner().plan(
        compactWriteRequest(setIndex: 0, valueToWrite: "BWx12@7", expectedCurrentValue: ""),
        in: grid
    )
    let setTwoUpdate = try SheetWritePlanner().plan(
        compactWriteRequest(setIndex: 1, valueToWrite: "BWx11@8", expectedCurrentValue: "BWx10@8"),
        in: grid
    )

    #expect(setOneUpdate.range == "'Block 27'!G18")
    #expect(setTwoUpdate.range == "'Block 27'!G19")
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

    #expect(update.range == "'Block 27'!G18")
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
    #expect(exercise.sets[1].setLog?.formatted == "BWx10@8")

    let setOneUpdate = try SheetWritePlanner().plan(
        compactWriteRequest(setIndex: 0, valueToWrite: "BWx12@7", expectedCurrentValue: "skip"),
        in: grid
    )

    #expect(setOneUpdate.range == "'Block 27'!G18")
}

private func compactLayoutGrid(headerNotes: String, continuationNotes: String) -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Last set RPE", "G14": "Notes",
            "C18": "Ab of Choice", "D18": "2", "G18": headerNotes,
            "G19": continuationNotes,
            "C20": "Bench Press", "D20": "1",
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
