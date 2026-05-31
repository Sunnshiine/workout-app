import Foundation
import Testing

@testable import WorkoutTracker

private final class StubWriteClient: SheetsClient, @unchecked Sendable {
    var titles: [String] = ["Block 27"]
    var grid: SheetGrid
    var updates: [(range: String, values: [[String]])] = []

    init(grid: SheetGrid) {
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { titles }
    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: grid)
    }
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        updates.append((range, values))
    }
}

private func writerFixture(_ cells: [String: String]) -> StubWriteClient {
    StubWriteClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes"
            ].merging(cells) { _, new in new },
            rows: 30,
            cols: 30
        )
    )
}

@Test func writesSetLogToNotesContinuationRow() async throws {
    let client = writerFixture(["C15": "Squat", "D15": "2", "K15": "Coach note"])
    let planner = SheetWritePlanner()
    let writer = SheetWriter(client: client)
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )

    let update = try planner.plan(request, in: client.grid)
    try await writer.write(update, spreadsheetId: "sid")

    #expect(client.updates.count == 1)
    #expect(client.updates[0].range == "'Block 27'!K16")
    #expect(client.updates[0].values == [["185x5@8"]])
}

@Test func writesSetOneToEmptyCompactHeaderNotes() throws {
    let client = writerFixture(["C15": "Ab of Choice", "D15": "1", "C16": "Bench"])
    let planner = SheetWritePlanner()
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Ab of Choice",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "25x12@7",
        expectedCurrentValue: ""
    )

    let update = try planner.plan(request, in: client.grid)

    #expect(update.range == "'Block 27'!K15")
    #expect(update.value == "25x12@7")
}

@Test func writesCompactSetTwoToHeaderNotesAggregate() throws {
    let client = writerFixture(["C15": "Ab of Choice", "D15": "2", "K15": "25x12@7", "C17": "Bench"])
    let planner = SheetWritePlanner()

    let setTwoUpdate = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Ab of Choice",
            setIndex: 1,
            column: .notes,
            operation: .upsert,
            valueToWrite: "25x12@8",
            expectedCurrentValue: ""
        ),
        in: client.grid
    )

    #expect(setTwoUpdate.range == "'Block 27'!K15")
    #expect(setTwoUpdate.value == "25x12@7, 25x12@8")
}

@Test func writesCoachNoteLayoutSetTwoToContinuationRow() throws {
    let planner = SheetWritePlanner()

    let setTwoUpdate = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Ab of Choice",
            setIndex: 1,
            column: .notes,
            operation: .upsert,
            valueToWrite: "25x12@8",
            expectedCurrentValue: ""
        ),
        in: writerFixture(["C15": "Ab of Choice", "D15": "2", "K15": "Coach note", "C18": "Bench"]).grid
    )

    #expect(setTwoUpdate.range == "'Block 27'!K17")
}

@Test func writesCompactSetTwoAfterApplyingSetOneToSnapshot() throws {
    let client = writerFixture(["C15": "Ab of Choice", "D15": "2", "C17": "Bench"])
    let planner = SheetWritePlanner()
    let snapshot = planner.snapshot(for: client.grid)

    let setOneUpdate = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Ab of Choice",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "25x12@7",
            expectedCurrentValue: ""
        ),
        in: snapshot
    )
    let updatedSnapshot = planner.applying(setOneUpdate, to: snapshot)
    let setTwoUpdate = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Ab of Choice",
            setIndex: 1,
            column: .notes,
            operation: .upsert,
            valueToWrite: "25x12@8",
            expectedCurrentValue: ""
        ),
        in: updatedSnapshot
    )

    #expect(setOneUpdate.range == "'Block 27'!K15")
    #expect(setOneUpdate.value == "25x12@7")
    #expect(setTwoUpdate.range == "'Block 27'!K15")
    #expect(setTwoUpdate.value == "25x12@7, 25x12@8")
}

@Test func editsExistingCompactHeaderSetLogWhenExpectedValueMatches() throws {
    let client = writerFixture(["C15": "Ab of Choice", "D15": "1", "K15": "25x12@7", "C16": "Bench"])
    let planner = SheetWritePlanner()
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Ab of Choice",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "30x12@8",
        expectedCurrentValue: "25x12@7"
    )

    let update = try planner.plan(request, in: client.grid)

    #expect(update.range == "'Block 27'!K15")
    #expect(update.value == "30x12@8")
}

@Test func matchingCoachNoteStillDoesNotMakeHeaderWritable() throws {
    let client = writerFixture(["C15": "Squat", "D15": "1", "K15": "Coach note", "C16": "Bench"])
    let planner = SheetWritePlanner()
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: "Coach note"
    )

    do {
        _ = try planner.plan(request, in: client.grid)
        Issue.record("Expected protected Coach Note to keep header unwritable")
    } catch let error as SheetWriterError {
        #expect(error == .headerNotesBlockSetRow(exerciseName: "Squat", setIndex: 0))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
}

@Test func defaultClientBatchUpdateRejectsMultipleUpdatesWithoutPartialWrites() async throws {
    let client = writerFixture(["C15": "Squat", "D15": "2"])
    let writer = SheetWriter(client: client)

    await #expect(throws: SheetsError.unsupportedBatchUpdate) {
        try await writer.write(
            [
                SheetCellUpdate(tabName: "Block 27", row: 15, col: 10, value: "185x5@8"),
                SheetCellUpdate(tabName: "Block 27", row: 16, col: 10, value: "195x5@8")
            ],
            spreadsheetId: "sid"
        )
    }

    #expect(client.updates.isEmpty)
}

@Test func protectsAnchorNotesByWritingBelowAnchor() async throws {
    let client = writerFixture(["C15": "Squat", "D15": "1", "K15": "Coach note"])
    let planner = SheetWritePlanner()
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )

    let update = try planner.plan(request, in: client.grid)

    #expect(update.range == "'Block 27'!K16")
}

@Test func writesLastSetRPEToAnchorRow() async throws {
    let client = writerFixture(["C15": "Squat", "D15": "2"])
    let planner = SheetWritePlanner()
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 1,
        column: .lastSetRPE,
        operation: .upsert,
        valueToWrite: "9",
        expectedCurrentValue: ""
    )

    let update = try planner.plan(request, in: client.grid)

    #expect(update.range == "'Block 27'!I15")
    #expect(update.value == "9")
}

@Test func resolvesShiftedNotesAndRPEColumnsFromRoleHeaders() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "E14": "Notes", "G14": "Last set RPE",
            "C15": "Squat", "D15": "2", "E15": "Coach note"
        ],
        rows: 30,
        cols: 30
    )
    let planner = SheetWritePlanner()

    let notesUpdate = try planner.plan(
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
        in: grid
    )
    let rpeUpdate = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Squat",
            setIndex: 1,
            column: .lastSetRPE,
            operation: .upsert,
            valueToWrite: "9",
            expectedCurrentValue: ""
        ),
        in: grid
    )

    #expect(notesUpdate.range == "'Block 27'!E16")
    #expect(rpeUpdate.range == "'Block 27'!G15")
}

@Test func resolvesShiftedExerciseRowsFromExerciseAnchors() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C18": "Squat", "D18": "2"
        ],
        rows: 30,
        cols: 30
    )
    let planner = SheetWritePlanner()

    let update = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Squat",
            setIndex: 1,
            column: .notes,
            operation: .upsert,
            valueToWrite: "195x5@8",
            expectedCurrentValue: ""
        ),
        in: grid
    )

    #expect(update.range == "'Block 27'!K18")
}

@Test func parserAndWriterAgreeOnShiftedCoachNoteContinuationRows() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "E14": "Notes", "G14": "Last set RPE",
            "C18": "Chest Fly", "D18": "2", "E18": "Keep elbows soft",
            "E19": "25x12@7",
            "E20": "20x10@8",
            "C25": "Bench Press", "D25": "1"
        ],
        rows: 32,
        cols: 30
    )

    let parsed = SheetParser().parse(grid: grid, tabName: "Block 27")
    let exercise = try #require(parsed.block.weeks.first?.days.first?.exercises.first)
    #expect(exercise.coachNote == "Keep elbows soft")
    #expect(exercise.sets.map { $0.setLog?.formatted } == ["25x12@7", "20x10@8"])

    let update = try SheetWritePlanner().plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Chest Fly",
            setIndex: 1,
            column: .notes,
            operation: .upsert,
            valueToWrite: "22.5x10@8",
            expectedCurrentValue: "20x10@8"
        ),
        in: grid
    )

    #expect(update.range == "'Block 27'!E20")
}

@Test func refusesUnexpectedCurrentCellValue() async throws {
    let client = writerFixture(["C15": "Squat", "D15": "1", "K15": "Coach note", "K16": "coach edited"])
    let planner = SheetWritePlanner()
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )

    do {
        _ = try planner.plan(request, in: client.grid)
        Issue.record("Expected unexpected current value")
    } catch let error as SheetWriterError {
        #expect(error == .unexpectedCurrentValue(expected: "", actual: "coach edited"))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
    #expect(client.updates.isEmpty)
}

@Test func refusesMissingContinuationRow() async throws {
    let client = writerFixture(["C15": "Squat", "D15": "1", "K15": "Coach note", "C16": "Bench"])
    let planner = SheetWritePlanner()
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )

    do {
        _ = try planner.plan(request, in: client.grid)
        Issue.record("Expected missing set row")
    } catch let error as SheetWriterError {
        #expect(error == .headerNotesBlockSetRow(exerciseName: "Squat", setIndex: 0))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
}

@Test func protectsLegacyLogByWritingSetLogToContinuationRow() throws {
    let client = writerFixture(["C15": "Squat", "D15": "2", "K15": "70@10, 80"])
    let planner = SheetWritePlanner()
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )

    let update = try planner.plan(request, in: client.grid)

    #expect(update.range == "'Block 27'!K16")
}

@Test func refusesMissingContinuationRowWhenLegacyLogFillsHeader() throws {
    let client = writerFixture(["C15": "Squat", "D15": "1", "K15": "70@10", "C16": "Bench"])
    let planner = SheetWritePlanner()
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )

    do {
        _ = try planner.plan(request, in: client.grid)
        Issue.record("Expected legacy log header to block writes when no safe continuation row")
    } catch let error as SheetWriterError {
        #expect(error == .headerNotesBlockSetRow(exerciseName: "Squat", setIndex: 0))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
}
