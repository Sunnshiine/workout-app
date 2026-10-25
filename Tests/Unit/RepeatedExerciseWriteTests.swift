import Foundation
import Testing

@testable import WorkoutTracker

/// A coach can name the same Exercise twice in one Session, as a top single and its back-off Sets
/// both named `Back Squat`. Each Set Log must still land on its own Exercise's row (#813).

private let frozenNow = Date(timeIntervalSince1970: 1_780_000_000)

/// The fresh-block workbook with W1 D1 holding `Back Squat` 1x1 on row 15 and `Back Squat` 3x5 on
/// row 19, where the RDL and its Coach Note were. `sheet` stands in for the coach editing the Sheet.
@MainActor
private func makeRepeatedExerciseApp(
    failedUpdateRequestNumbers: Set<Int> = []
) async throws -> (app: WorkoutApplication, sheet: LocalWorkbookSheetsClient) {
    var workbook = WorkbookScenario.freshBlock.workbook()
    var tab = try #require(workbook.tabs["Block 27"])
    tab.cells.merge(
        ["C15": "Back Squat", "D15": "1", "F15": "1", "H15": "RPE8", "C19": "Back Squat", "D19": "3", "F19": "5", "H19": "RPE7"]
    ) { _, new in new }
    tab.cells["K19"] = nil
    workbook.tabs["Block 27"] = tab
    let sheet = LocalWorkbookSheetsClient(workbook: workbook, failedUpdateRequestNumbers: failedUpdateRequestNumbers)
    let app = try WorkoutApplication(environment: .inMemory(sheets: sheet, now: { frozenNow }))
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
    return (app, sheet)
}

@MainActor
private func coachEdits(_ sheet: LocalWorkbookSheetsClient, _ a1: String, to value: String) async throws {
    try await sheet.write([SheetCellWrite(tabName: "Block 27", a1: a1, value: value)], spreadsheetId: "FIXTURE")
}

private func address(_ raw: String) throws -> SetAddress {
    try #require(SetAddress(raw))
}

@MainActor
@Test func eachSameNamedExerciseFlushesItsSetLogToItsOwnRow() async throws {
    let (app, _) = try await makeRepeatedExerciseApp()

    _ = try app.log(address("w1d1.e0.s0"), setLog: "400x1@8")
    _ = try app.log(address("w1d1.e1.s0"), setLog: "330x5@7")
    let flush = try await app.flush()

    #expect(flush.conflictedWrites == [])
    let sheet = try await app.sheet(tab: nil)
    #expect(sheet.cells["K15"] == "400x1@8")
    #expect(sheet.cells["I15"] == "8")
    #expect(sheet.cells["K19"] == "330x5@7")
}

@MainActor
@Test func aSkipOnTheSecondSameNamedExerciseRewritesItsOwnRow() async throws {
    let (app, _) = try await makeRepeatedExerciseApp()

    _ = try app.log(address("w1d1.e0.s0"), setLog: "400x1@8")
    _ = try app.log(address("w1d1.e1.s0"), setLog: "330x5@7")
    _ = try app.skip(address("w1d1.e1.s0"))
    let flush = try await app.flush()

    #expect(flush.conflictedWrites == [])
    let sheet = try await app.sheet(tab: nil)
    #expect(sheet.cells["K15"] == "400x1@8")
    #expect(sheet.cells["K19"] == "skip")

    _ = try await app.sync()
    let session = try app.session(SessionAddress(week: 1, day: 1))
    #expect(session.exercises[0].sets[0].state == "logged")
    #expect(session.exercises[1].sets[0].state == "skipped")
}

@MainActor
@Test func aConflictOnTheSecondSameNamedExerciseLeavesTheFirstOnesLastSetRPEToLand() async throws {
    let (app, sheet) = try await makeRepeatedExerciseApp()

    _ = try app.log(address("w1d1.e1.s0"), setLog: "330x5@7")
    _ = try app.log(address("w1d1.e0.s0"), setLog: "400x1@8")
    try await coachEdits(sheet, "K19", to: "300x5@7")
    let flush = try await app.flush()

    #expect(flush.conflictedWrites == ["Back Squat: Expected '', found '300x5@7'"])
    let cells = try await app.sheet(tab: nil).cells
    #expect(cells["K15"] == "400x1@8")
    #expect(cells["I15"] == "8")
}

@MainActor
@Test func aSyncShowsAPendingSetLogOnTheSameNamedExerciseItWasLoggedOn() async throws {
    let (app, _) = try await makeRepeatedExerciseApp(failedUpdateRequestNumbers: [1])

    _ = try app.log(address("w1d1.e1.s0"), setLog: "330x5@7")
    let report = try await app.sync()

    #expect(report.pendingWriteCount == 1)
    let session = try app.session(SessionAddress(week: 1, day: 1))
    #expect(session.exercises[0].sets[0].state == "pending")
    #expect(session.exercises[1].sets[0].state == "logged")
    #expect(session.exercises[1].sets[0].setLog == "330x5@7")
}

@MainActor
@Test func renamingTheFirstSameNamedExerciseConflictsTheSecondOnesWriteByItsNumber() async throws {
    let (app, sheet) = try await makeRepeatedExerciseApp()

    _ = try app.log(address("w1d1.e1.s0"), setLog: "330x5@7")
    try await coachEdits(sheet, "C15", to: "Front Squat")
    let flush = try await app.flush()

    #expect(flush.conflictedWrites == ["Back Squat: Back Squat number 2 was not found in the sheet"])
    #expect(try await app.sheet(tab: nil).cells["K19"] == nil)
}

@MainActor
@Test func theSecondSameNamedExerciseHasItsOwnSetCoordinates() throws {
    let block = Block(tabName: "Block 27")
    let week = Week(number: 1)
    week.block = block
    block.weeks = [week]
    let session = Session(dayNumber: 1, date: nil)
    session.week = week
    week.sessions = [session]
    // Inserted out of Sheet order: the ordinal follows `order`, not the relationship's array.
    let backOff = Exercise(name: "Back Squat", coachNote: nil, order: 2)
    let accessory = Exercise(name: "RDL", coachNote: nil, order: 1)
    let topSingle = Exercise(name: "Back Squat", coachNote: nil, order: 0)
    session.exercises = [backOff, accessory, topSingle]
    for exercise in session.exercises {
        let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE7", percentOneRM: nil, state: .pending)
        set.exercise = exercise
        exercise.sets = [set]
    }

    #expect(try SetCoordinates(of: topSingle.sets[0]).exercise == .unchecked(name: "Back Squat", ordinal: 0))
    #expect(try SetCoordinates(of: accessory.sets[0]).exercise == .unchecked(name: "RDL", ordinal: 0))
    #expect(try SetCoordinates(of: backOff.sets[0]).exercise == .unchecked(name: "Back Squat", ordinal: 1))
    #expect(block.setsByID.count == 3)
    let backOffID = SetCoordinates.ID(
        session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
        exercise: .unchecked(name: "Back Squat", ordinal: 1),
        setIndex: 0
    )
    #expect(block.setsByID[backOffID] === backOff.sets[0])
}

private func backSquatRequest(ordinal: Int) -> SheetWriteRequest {
    SheetWriteRequest(
        session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
        exercise: .unchecked(name: "Back Squat", ordinal: ordinal),
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )
}

private func backSquatTwiceGrid(_ extra: [String: String] = [:]) -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Back Squat", "D15": "1", "C17": "RDL", "D17": "2", "C19": "Back Squat", "D19": "3"
        ].merging(extra) { _, new in new },
        rows: 30,
        cols: 30
    )
}

@Test func thePlannerAddressesTheNthExerciseOfThatName() throws {
    let grid = backSquatTwiceGrid()
    let planner = SheetWritePlanner()

    #expect(try planner.plan(backSquatRequest(ordinal: 0), in: grid).row == 14)
    #expect(try planner.plan(backSquatRequest(ordinal: 1), in: grid).row == 18)
    #expect(throws: SheetWriterError.exerciseNotFound(.unchecked(name: "Back Squat", ordinal: 2))) {
        try planner.plan(backSquatRequest(ordinal: 2), in: grid)
    }
}

@Test func aCoachNoteOnTheSecondSameNamedExerciseNamesItByItsNumber() throws {
    let grid = backSquatTwiceGrid(["D19": "1", "K19": "Coach note", "C20": "Bench", "D20": "1"])

    let error = #expect(throws: SheetWriterError.self) {
        try SheetWritePlanner().plan(backSquatRequest(ordinal: 1), in: grid)
    }

    #expect(error == .headerNotesBlockSetRow(exercise: .unchecked(name: "Back Squat", ordinal: 1), setIndex: 0))
    #expect(error?.errorDescription?.hasPrefix("Set 1 for Back Squat number 2 cannot be written") == true)
}

@Test func theWriteAuditNamesAMissingSameNamedExerciseByItsNumber() {
    let planner = SheetWritePlanner()
    let request = backSquatRequest(ordinal: 2)

    let audit = planner.auditDetails(
        for: request,
        error: .exerciseNotFound(request.exercise),
        in: planner.snapshot(for: backSquatTwiceGrid()),
        target: nil
    )

    #expect(audit.rowScanDetails == "No row selected: Back Squat number 3 was not found in Week 1, Day 1.")
}
