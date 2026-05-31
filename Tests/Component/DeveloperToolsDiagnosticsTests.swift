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
