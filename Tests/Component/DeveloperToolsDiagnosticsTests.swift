import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func pendingWriteDiagnosticShowsCompactWriteContext() throws {
    let write = PendingWrite(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000086") ?? UUID(),
        blockTab: "Block 27",
        week: 2,
        day: 3,
        exerciseName: "Back Squat",
        setIndex: 1,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )
    write.markConflict("Expected empty cell")

    let diagnostic = PendingWriteDiagnostic(write: write)

    #expect(diagnostic.id == write.id)
    #expect(diagnostic.block == "Block 27")
    #expect(diagnostic.week == "Week 2")
    #expect(diagnostic.day == "Day 3")
    #expect(diagnostic.exercise == "Back Squat")
    #expect(diagnostic.set == "Set 2")
    #expect(diagnostic.column == "Notes")
    #expect(diagnostic.value == "185x5@8")
    #expect(diagnostic.status == "Conflict")
    #expect(diagnostic.error == "Expected empty cell")
}

@MainActor
@Test func auditDetailsReportsPerLineValueForMultiLineWrite() throws {
    // A multi-line (J. Alarcon) Exercise: Comp BP = a 1-set anchor Line plus a 2-set
    // continuation Line at row 16 whose Notes cell already holds Set 2's log. Logging Set 3
    // (position 1 of that Line) succeeds; the audit must report the per-position value, not the
    // whole cell — otherwise a successful write is logged as a value mismatch.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "J14": "Notes",
            "C15": "Comp BP", "D15": "1", "F15": "5", "H15": "RPE6",
            "D16": "2", "F16": "7", "H16": "RPE5, RPE6", "J16": "135x7@8",
            "C17": "Hip Thrust", "D17": "2"
        ],
        rows: 24,
        cols: 30
    )
    let planner = SheetWritePlanner()
    let snapshot = planner.snapshot(for: grid)
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Comp BP",
        setIndex: 2,
        column: .notes,
        operation: .upsert,
        valueToWrite: "140x7@9",
        expectedCurrentValue: ""
    )

    let target = try planner.target(for: request, in: snapshot)
    let audit = planner.auditDetails(for: request, target: target, in: snapshot)

    #expect(audit.selectedA1Target == "'Block 27'!J16")
    #expect(audit.currentValue == "")
    #expect(audit.valueCheckOutcome == "Current value matched expected ''.")
    #expect(audit.rowScanDetails.contains("Prescription Line"))
}

@MainActor
@Test func auditReportsDriftAgainstSharedCompactAggregateHeaderRule() throws {
    // A compact aggregate header: "Ab of Choice" keeps both Sets' logs comma-separated in its
    // anchor Notes cell (K15 = "25x12@7, skip"). Logging Set 2 expects an empty slot, but the
    // persisted slot reads "skip". The audit must classify the cell through the shared Set Log
    // token rule, split it, and report the per-Set drift — not the whole-cell value. If the audit
    // stopped cross-checking against the shared classification it would report the raw cell and
    // miss the mismatch.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Ab of Choice", "D15": "2", "K15": "25x12@7, skip",
            "C17": "Bench"
        ],
        rows: 24,
        cols: 30
    )
    let planner = SheetWritePlanner()
    let snapshot = planner.snapshot(for: grid)
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Ab of Choice",
        setIndex: 1,
        column: .notes,
        operation: .upsert,
        valueToWrite: "25x12@8",
        expectedCurrentValue: ""
    )

    let target = try planner.target(for: request, in: snapshot)
    let audit = planner.auditDetails(for: request, target: target, in: snapshot)

    #expect(audit.selectedA1Target == "'Block 27'!K15")
    #expect(audit.currentValue == "skip")
    #expect(audit.valueCheckOutcome == "Expected '', found 'skip'.")
    #expect(audit.rowScanDetails.contains("comma-separated list"))
}

@MainActor
@Test func auditReportsPerSetValueForProtectedHeaderVisibleWritableRowPlacement() throws {
    // A protected coach-note header (K15) redirects Set logs to the first Visible Writable Row
    // below it (K16), which already holds both Sets' logs as a comma-separated list. Logging Set 2
    // expects an empty slot, but the persisted slot reads "190x5@8". The audit must read the value
    // at the placement's list position — not the whole writable-row cell — so protected-header
    // drift is caught, and the scan must keep its "protected header" wording.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "2", "K15": "Coach note",
            "K16": "185x5@8, 190x5@8",
            "C19": "Bench Press", "D19": "1"
        ],
        rows: 24,
        cols: 30
    )
    let planner = SheetWritePlanner()
    let snapshot = planner.snapshot(for: grid)
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 1,
        column: .notes,
        operation: .upsert,
        valueToWrite: "195x5@9",
        expectedCurrentValue: ""
    )

    let target = try planner.target(for: request, in: snapshot)
    let audit = planner.auditDetails(for: request, target: target, in: snapshot)

    #expect(audit.selectedA1Target == "'Block 27'!K16")
    #expect(audit.currentValue == "190x5@8")
    #expect(audit.valueCheckOutcome == "Expected '', found '190x5@8'.")
    #expect(audit.rowScanDetails.contains("first visible writable row below protected header Notes"))
}

@MainActor
@Test func writeTargetAuditConsumesSamePlacementDecisionAsReaderAndWriter() throws {
    // The audit must read its target cell and per-Set value from the one placement query the reader
    // and writer consume — not a re-derived addressing tree. For a compact-aggregate header storing
    // both Sets in the anchor Notes cell, Set 2 resolves to the anchor row, Notes column, list
    // position 1; the writer's target and the audit's selected cell / current value must match that
    // one placement, closing the read/write/audit divergence.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Ab of Choice", "D15": "2", "K15": "25x12@7, 25x12@8",
            "C17": "Bench"
        ],
        rows: 24,
        cols: 30
    )
    let anchorSnapshot = SheetSnapshot(values: grid)
    let layout = SheetLayoutInterpreter().interpret(grid)
    let day = try #require(layout.day(week: 1, day: 1))
    let anchor = try #require(day.exerciseAnchors.first { $0.name == "Ab of Choice" })
    guard case .placed(let placement) = anchor.setLogPlacement(for: 1, in: anchorSnapshot, cols: day.columns) else {
        Issue.record("Expected a resolved placement for Set 2")
        return
    }
    let position = try #require(placement.listPosition)

    let planner = SheetWritePlanner()
    let planningSnapshot = planner.snapshot(for: grid)
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Ab of Choice",
        setIndex: 1,
        column: .notes,
        operation: .upsert,
        valueToWrite: "25x12@9",
        expectedCurrentValue: "25x12@8"
    )
    let target = try planner.target(for: request, in: planningSnapshot)
    let audit = planner.auditDetails(for: request, target: target, in: planningSnapshot)

    // Writer target and audit selection both land on the placement's resolved cell.
    #expect(target.row == placement.row)
    #expect(target.col == placement.col)
    #expect(audit.selectedA1Target == singleCellRange(tabName: "Block 27", row: placement.row, col: placement.col))
    // The audit's per-Set current value is the placement's list slot — the same token the reader reads.
    let placementValue = SetLogList(cell: grid.cell(row: placement.row, col: placement.col)).token(at: position)
    #expect(audit.currentValue == placementValue)
    #expect(placementValue == "25x12@8")
}

@MainActor
@Test func syncCoordinatorListsPendingAndConflictedWriteDiagnosticsInCreationOrder() throws {
    let container = try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let laterPending = makeDiagnosticWrite(
        createdAt: Date(timeIntervalSinceReferenceDate: 2),
        exerciseName: "Bench Press",
        valueToWrite: nil
    )
    let earlierConflict = makeDiagnosticWrite(
        createdAt: Date(timeIntervalSinceReferenceDate: 1),
        exerciseName: "Back Squat",
        valueToWrite: "185x5@8"
    )
    earlierConflict.markConflict("Cell changed")
    context.insert(laterPending)
    context.insert(earlierConflict)
    try context.save()

    let sync = SyncCoordinator(client: DiagnosticStubClient(), context: context)

    let diagnostics = try sync.pendingWriteDiagnostics()

    #expect(diagnostics.map(\.exercise) == ["Back Squat", "Bench Press"])
    #expect(diagnostics.map(\.status) == ["Conflict", "Pending"])
    #expect(diagnostics[1].value == "Delete")
}

@MainActor
@Test func writeTargetAuditDiagnosticCopyTextIncludesDecisionDetails() throws {
    let entry = WriteTargetAuditEntry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000110") ?? UUID(),
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        blockTab: "Block 27",
        week: 2,
        day: 3,
        exerciseName: "Back Squat",
        setIndex: 1,
        column: .notes,
        selectedA1Target: "'Block 27'!K17",
        rowScanDetails: "Skipped hidden rows: row 16 hidden by user. Selected row 17.",
        expectedCurrentValue: "",
        currentValue: "",
        valueCheckOutcome: "Current value matched expected ''.",
        finalStatus: .succeeded,
        message: nil
    )

    let diagnostic = WriteTargetAuditDiagnostic(entry: entry)
    let copyText = WriteTargetAuditDiagnostic.copyText(for: [diagnostic])

    #expect(diagnostic.target == "'Block 27'!K17")
    #expect(diagnostic.status == "Succeeded")
    #expect(copyText.contains("Write Target Audit Log"))
    #expect(copyText.contains("Block 27, Week 2, Day 3, Back Squat, Set 2, Notes"))
    #expect(copyText.contains("Selected target: 'Block 27'!K17"))
    #expect(copyText.contains("Row scan: Skipped hidden rows: row 16 hidden by user. Selected row 17."))
    #expect(copyText.contains("Value check: Current value matched expected ''."))
    #expect(copyText.contains("Final status: Succeeded"))
}

@MainActor
@Test func clearingWriteTargetAuditLogDoesNotDeletePendingOrConflictedWrites() throws {
    let container = try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let pending = makeDiagnosticWrite(
        createdAt: Date(timeIntervalSinceReferenceDate: 1),
        exerciseName: "Back Squat",
        valueToWrite: "185x5@8"
    )
    let conflict = makeDiagnosticWrite(
        createdAt: Date(timeIntervalSinceReferenceDate: 2),
        exerciseName: "Bench Press",
        valueToWrite: "135x5@7"
    )
    conflict.markConflict("Cell changed")
    context.insert(pending)
    context.insert(conflict)
    context.insert(makeAuditEntry(exerciseName: "Back Squat"))
    try context.save()
    let sync = SyncCoordinator(client: DiagnosticStubClient(), context: context)

    try sync.clearWriteTargetAuditLog()

    let writes = try context.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.map(\.exerciseName).sorted() == ["Back Squat", "Bench Press"])
    #expect(try context.fetch(FetchDescriptor<WriteTargetAuditEntry>()).isEmpty)
}

private func makeDiagnosticWrite(
    createdAt: Date,
    exerciseName: String,
    valueToWrite: String?
) -> PendingWrite {
    PendingWrite(
        createdAt: createdAt,
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: exerciseName,
        setIndex: 0,
        column: .notes,
        operation: valueToWrite == nil ? .delete : .upsert,
        valueToWrite: valueToWrite,
        expectedCurrentValue: ""
    )
}

private func makeAuditEntry(exerciseName: String) -> WriteTargetAuditEntry {
    WriteTargetAuditEntry(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: exerciseName,
        setIndex: 0,
        column: .notes,
        selectedA1Target: "'Block 27'!K15",
        rowScanDetails: "Selected row 15.",
        expectedCurrentValue: "",
        currentValue: "",
        valueCheckOutcome: "Current value matched expected ''.",
        finalStatus: .succeeded,
        message: nil
    )
}

private struct DiagnosticStubClient: SheetsClient {
    func listTabTitles(spreadsheetId: String) async throws -> [String] { [] }
    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: [])
    }
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}
