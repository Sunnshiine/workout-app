import Foundation
import Testing

@testable import WorkoutTracker

@Test func rowScanNarratesEveryResolvedSetLogPlacementKind() {
    // Multi-line Prescription Line: Comp BP is a 1-Set anchor Line plus a 2-Set Line at row 16, so
    // Set 3 is position 2 of that Line's comma-separated Notes cell.
    #expect(
        auditRowScan(
            cells: [
                "C15": "Comp BP", "D15": "1", "F15": "5",
                "D16": "2", "F16": "7", "K16": "135x7@8",
                "C17": "Hip Thrust", "D17": "2"
            ],
            exercise: "Comp BP",
            setIndex: 2
        )
            == """
            Selected row 16: Prescription Line row stores this Line's Set logs as a comma-separated list \
            (Set 2 of the Line).
            """
    )

    #expect(
        auditRowScan(
            cells: [
                "C15": "Ab of Choice", "D15": "2", "K15": "25x12@7, 25x12@8",
                "C17": "Bench", "D17": "1"
            ],
            exercise: "Ab of Choice",
            setIndex: 1
        )
            == "Selected row 15: compact header Notes row stores Set logs as a comma-separated list."
    )

    #expect(
        auditRowScan(
            cells: [
                "C15": "Squat", "D15": "2", "K15": "Coach note", "K16": "185x5@8",
                "C19": "Bench Press", "D19": "1"
            ],
            exercise: "Squat",
            setIndex: 1
        )
            == """
            Selected row 16: first visible writable row below protected header Notes before the next \
            Exercise.
            """
    )

    // A Set past the prescribed count falls through the list rules onto its own visible Set row.
    #expect(
        auditRowScan(
            cells: ["C15": "Squat", "D15": "2", "C19": "Bench", "D19": "1"],
            exercise: "Squat",
            setIndex: 2
        )
            == "Selected row 17: visible Set row for Set 3."
    )
}

@Test func rowScanNarratesTheScanThatFoundNoRow() {
    // Every candidate row below the anchor is hidden, so the scan names each skipped row and its
    // reason before reporting that no visible Set row exists.
    #expect(
        auditRowScan(
            cells: ["C15": "Squat", "D15": "1", "C18": "Bench", "D18": "1"],
            rowVisibility: [
                15: SheetRowVisibility(hiddenByUser: true, hiddenByFilter: true),
                16: SheetRowVisibility(hiddenByFilter: true)
            ],
            exercise: "Squat",
            setIndex: 1
        )
            == """
            Skipped hidden rows: row 16 hidden by user and filter, row 17 hidden by filter. No row \
            selected: no visible Set row found for Set 2 before the next Exercise.
            """
    )

    // A protected coach-note header with no writable row before the next Exercise.
    #expect(
        auditRowScan(
            cells: ["C15": "Squat", "D15": "2", "K15": "Coach note", "C16": "Bench", "D16": "1"],
            exercise: "Squat",
            setIndex: 0
        )
            == "No row selected: no visible writable row below protected header Notes before the next Exercise."
    )

    // No Notes column at all: Set Logs cannot be placed anywhere.
    #expect(
        auditRowScan(
            cells: ["C15": "Squat", "D15": "2", "C19": "Bench", "D19": "1"],
            notesHeader: false,
            exercise: "Squat",
            setIndex: 0
        )
            == "No row selected: no visible Set row found for Set 1 before the next Exercise."
    )
}

@Test func rowScanReportsThatAHiddenPrescriptionLineRowPrescribesNothing() {
    #expect(
        auditRowScan(
            cells: [
                "C15": "Comp BP", "D15": "1", "F15": "5",
                "D16": "2", "F16": "7",
                "C17": "Hip Thrust", "D17": "2"
            ],
            rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)],
            exercise: "Comp BP",
            setIndex: 2
        )
            == """
            Skipped hidden rows: row 16 hidden by user. No row selected: no visible Set row found for \
            Set 3 before the next Exercise.
            """
    )
}

@Test func rowScanNarratesLastSetRPEAgainstTheExerciseRow() {
    #expect(
        auditRowScan(
            cells: ["C15": "Squat", "D15": "2", "C19": "Bench", "D19": "1"],
            exercise: "Squat",
            setIndex: 1,
            column: .lastSetRPE
        )
            == "Selected row 15: visible Exercise row for Last Set RPE."
    )

    #expect(
        auditRowScan(
            cells: ["C15": "Squat", "D15": "2", "C19": "Bench", "D19": "1"],
            rowVisibility: [14: SheetRowVisibility(hiddenByUser: true)],
            exercise: "Squat",
            setIndex: 1,
            column: .lastSetRPE
        )
            == "No row selected: Squat was not found in Week 1, Day 1."
    )
}

@Test func rowScanNamesTheMissingSessionOrExerciseBeforeItScansRows() {
    let cells = ["C15": "Squat", "D15": "2", "C19": "Bench", "D19": "1"]

    #expect(
        auditRowScan(cells: cells, day: 9, exercise: "Squat", setIndex: 0)
            == "No row selected: Week 1, Day 9 was not found."
    )
    #expect(
        auditRowScan(cells: cells, exercise: "Deadlift", setIndex: 0)
            == "No row selected: Deadlift was not found in Week 1, Day 1."
    )
}

/// Drives the real audit path for one write: a resolved target audits with that target, and a write
/// the planner refuses audits with the error and no target — the two ways the Write Target Audit Log
/// gets its row scan.
private func auditRowScan(
    cells: [String: String],
    rowVisibility: [Int: SheetRowVisibility] = [:],
    notesHeader: Bool = true,
    day: Int = 1,
    exercise: String,
    setIndex: Int,
    column: PendingWriteColumn = .notes
) -> String {
    var allCells = [
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE"
    ]
    if notesHeader { allCells["K14"] = "Notes" }
    allCells.merge(cells) { _, new in new }

    let planner = SheetWritePlanner()
    let snapshot = planner.snapshot(
        for: SheetSnapshot(
            values: gridFromA1(allCells, rows: 24, cols: 30),
            rowVisibility: rowVisibility
        )
    )
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: day,
        exerciseName: exercise,
        setIndex: setIndex,
        column: column,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )

    do {
        let target = try planner.target(for: request, in: snapshot)
        return planner.auditDetails(for: request, target: target, in: snapshot).rowScanDetails
    } catch let error as SheetWriterError {
        return planner.auditDetails(for: request, error: error, in: snapshot, target: nil).rowScanDetails
    } catch {
        return "unexpected error: \(error)"
    }
}
