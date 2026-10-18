import Foundation
import Testing

@testable import WorkoutTracker

private func multiLinePrescriptionGrid(_ extra: [String: String] = [:]) -> SheetGrid {
    // J. Alarcon template: Comp SQ = two 1-set lines (rows 15,16);
    // Comp BP = a 1-set line (row 17) then a 2-set line (row 18); Hip Thrust bounds the span.
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "J14": "Notes",
            "C15": "Comp SQ", "D15": "1", "F15": "5", "H15": "RPE6",
            "D16": "1", "F16": "5", "H16": "Drop 20%",
            "C17": "Comp BP", "D17": "1", "F17": "5", "H17": "RPE6",
            "D18": "2", "F18": "7", "H18": "RPE5, RPE6",
            "C19": "Hip Thrust", "D19": "2"
        ].merging(extra) { _, new in new },
        rows: 26,
        cols: 30
    )
}

private func multiLineNotesRequest(
    _ name: String,
    _ setIndex: Int,
    value: String,
    expected: String = ""
) -> SheetWriteRequest {
    SheetWriteRequest(
        session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
        exerciseName: name,
        setIndex: setIndex,
        column: .notes,
        operation: .upsert,
        valueToWrite: value,
        expectedCurrentValue: expected
    )
}

@Test func writesMultiLineSetsToTheirOwnPrescriptionRows() throws {
    let planner = SheetWritePlanner()
    let grid = multiLinePrescriptionGrid()

    #expect(
        try planner.plan(multiLineNotesRequest("Comp SQ", 0, value: "135x5@6"), in: grid).target
            == SheetWriteTarget(tabName: "Block 27", a1: "J15")
    )
    #expect(
        try planner.plan(multiLineNotesRequest("Comp SQ", 1, value: "115x5@7"), in: grid).target
            == SheetWriteTarget(tabName: "Block 27", a1: "J16")
    )
    #expect(
        try planner.plan(multiLineNotesRequest("Comp BP", 0, value: "95x5@6"), in: grid).target
            == SheetWriteTarget(tabName: "Block 27", a1: "J17")
    )

    let bpSetTwo = try planner.plan(multiLineNotesRequest("Comp BP", 1, value: "135x7@8"), in: grid)
    #expect(bpSetTwo == SheetCellWrite(tabName: "Block 27", a1: "J18", value: "135x7@8"))
}

@Test func aggregatesMultiSetLineLogsWithinOneNotesCell() throws {
    let planner = SheetWritePlanner()
    let grid = multiLinePrescriptionGrid(["J18": "135x7@8"])

    let bpSetThree = try planner.plan(multiLineNotesRequest("Comp BP", 2, value: "140x7@9"), in: grid)

    #expect(bpSetThree == SheetCellWrite(tabName: "Block 27", a1: "J18", value: "135x7@8, 140x7@9"))
}

@Test func refusesToOverwriteLegacyLogOnMultiLinePrescriptionLine() throws {
    // Coach-data safety across the split placement/protection boundary: a multi-line Prescription
    // Line whose Notes cell holds a Legacy Log (ADR-0005) is read as Pending, so the write arrives
    // expecting an empty slot. The placement query still resolves that Line's cell, but the value
    // check must conflict rather than overwrite the coach's Legacy Log. This pins the invariant the
    // reader enforces (leaving the Set Pending) on the writer side too.
    let planner = SheetWritePlanner()
    let grid = multiLinePrescriptionGrid(["J15": "70@10, 80"])

    do {
        _ = try planner.plan(multiLineNotesRequest("Comp SQ", 0, value: "135x5@6"), in: grid)
        Issue.record("Expected the Legacy-Log line write to conflict")
    } catch let error as SheetWriterError {
        #expect(error == .unexpectedCurrentValue(expected: "", actual: "70@10"))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
}

@Test func aCoachNoteLineLogsToTheSpareRowAndReadsBackLogged() throws {
    // #942: the anchor Line's Notes cell holds a Coach Note, so Set 1 lands on the first spare row
    // of the Exercise (row 18 here, below Comp BP's two Lines) and the Coach Note stays as written.
    let parser = SheetParser()
    let planner = SheetWritePlanner()
    let coachNote = "Brace hard, controlled descent"
    let snapshot = planner.snapshot(
        for: multiLinePrescriptionGrid(["J17": coachNote, "C19": "", "D19": "", "C20": "Hip Thrust", "D20": "2"])
    )

    let update = try planner.plan(multiLineNotesRequest("Comp BP", 0, value: "95x5@6"), in: snapshot)
    #expect(update == SheetCellWrite(tabName: "Block 27", a1: "J19", value: "95x5@6"))

    let after = planner.applying(update, to: snapshot)
    #expect(after.grid.cell(row: 16, col: 9) == coachNote)
    let compBP = try #require(parser.parse(grid: after.grid, tabName: "Block 27").block.weeks.first?.days.first?.exercises[1])
    #expect(compBP.coachNote == coachNote)
    #expect(compBP.sets.map(\.state) == [.logged, .pending, .pending])
    #expect(compBP.sets[0].setLog == SetLog(weight: .pounds(95), reps: 5, rpe: .six))
}

@Test func aCoachNoteLineWithoutASpareRowNamesTheProtectedNotes() throws {
    // Comp BP's Lines fill its span, so the Coach Note leaves its first Set nowhere to go. The
    // refusal names the Exercise and the protected Notes, not the Coach Note's first comma fragment.
    let planner = SheetWritePlanner()
    let grid = multiLinePrescriptionGrid(["J17": "Brace hard, controlled descent"])

    do {
        _ = try planner.plan(multiLineNotesRequest("Comp BP", 0, value: "95x5@6"), in: grid)
        Issue.record("Expected the Coach Note Line write to be refused")
    } catch let error as SheetWriterError {
        #expect(error == .headerNotesBlockSetRow(exerciseName: "Comp BP", setIndex: 0))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
}

@Test func parserAndWriterAgreeOnMultiLinePrescriptionSets() throws {
    let parser = SheetParser()
    let planner = SheetWritePlanner()
    let snapshot = planner.snapshot(for: multiLinePrescriptionGrid())

    let compBP = try #require(
        parser.parse(grid: snapshot.grid, tabName: "Block 27").block.weeks.first?.days.first?.exercises[1]
    )
    #expect(compBP.exerciseName.base == "Comp BP")
    #expect(compBP.sets.count == 3)

    let afterSetTwo = planner.applying(
        try planner.plan(multiLineNotesRequest("Comp BP", 1, value: "135x7@8"), in: snapshot),
        to: snapshot
    )
    let afterSetThree = planner.applying(
        try planner.plan(multiLineNotesRequest("Comp BP", 2, value: "140x7@9"), in: afterSetTwo),
        to: afterSetTwo
    )

    let reparsed = try #require(
        parser.parse(grid: afterSetThree.grid, tabName: "Block 27").block.weeks.first?.days.first?.exercises[1]
    )
    #expect(reparsed.sets[0].state == .pending)
    #expect(reparsed.sets[1].setLog == SetLog(weight: .pounds(135), reps: 7, rpe: .eight))
    #expect(reparsed.sets[2].setLog == SetLog(weight: .pounds(140), reps: 7, rpe: .nine))
}
