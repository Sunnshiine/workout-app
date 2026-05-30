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

private struct DiagnosticStubClient: SheetsClient {
    func listTabTitles(spreadsheetId: String) async throws -> [String] { [] }
    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid { [] }
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}
