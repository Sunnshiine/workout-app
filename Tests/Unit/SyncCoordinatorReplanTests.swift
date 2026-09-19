import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

/// Serves a scripted snapshot per fetch, so a test can move the Sheet between the flush's first read
/// of a tab and any later read of the same tab.
private final class ScriptedSnapshotClient: SheetsClient, @unchecked Sendable {
    private var scriptedGrids: [SheetGrid]
    private(set) var fetchCount = 0
    private(set) var updates: [(range: String, values: [[String]])] = []

    init(grids: [SheetGrid]) {
        self.scriptedGrids = grids
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        fetchCount += 1
        let grid = scriptedGrids.count > 1 ? scriptedGrids.removeFirst() : (scriptedGrids.first ?? [])
        return SheetSnapshot(values: grid)
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        updates.append((range, values))
    }

    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
        self.updates.append(contentsOf: updates.map { ($0.range, $0.values) })
    }
}

@MainActor
private func makeReplanContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func replanPendingWrite(
    createdAt: TimeInterval,
    valueToWrite: String,
    expectedCurrentValue: String
) -> PendingWrite {
    PendingWrite(
        createdAt: Date(timeIntervalSince1970: createdAt),
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: valueToWrite,
        expectedCurrentValue: expectedCurrentValue
    )
}

private func squatOneSetGrid(notes: String? = nil) -> SheetGrid {
    var cells = [
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
        "C15": "Squat", "D15": "1"
    ]
    if let notes {
        cells["K15"] = notes
    }
    return gridFromA1(cells, rows: 24, cols: 30)
}

/// Two queued Notes writes for the same Set resolve to the same cell, so planning the second one
/// against the batch's in-memory snapshot fails its expected-current-value check. The flush writes
/// the batch out early and then reports the second write as a conflict.
///
/// The re-plan that follows the early write reads the same per-flush snapshot cache that produced
/// the failure, so it sees the value the batch predicted rather than the Sheet: the second scripted
/// grid here holds exactly what the second write expects, and the conflict is raised anyway against
/// the predicted `185x5@8`. The client is never asked for the tab a second time.
@MainActor
@Test func planningFailureOnAnAlreadyBatchedTargetWritesThatBatchThenConflicts() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = ScriptedSnapshotClient(grids: [squatOneSetGrid(), squatOneSetGrid(notes: "205x3@9")])
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.fetchCount == 1)
    #expect(client.updates.map(\.range) == ["'Block 27'!K15"])
    #expect(client.updates.map(\.values) == [[["185x5@8"]]])
    #expect(sync.outcome == .writesRefused(["Squat: Expected '205x3@9', found '185x5@8'"]))

    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(remaining.count == 1)
    #expect(remaining.first?.status == .conflict)
    #expect(remaining.first?.valueToWrite == "205x3@10")

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    #expect(entries.map(\.finalStatus).sorted { $0.rawValue < $1.rawValue } == [.conflict, .succeeded])
    let conflictEntry = try #require(entries.first { $0.finalStatus == .conflict })
    #expect(conflictEntry.selectedA1Target == "'Block 27'!K15")
    #expect(conflictEntry.currentValue == "185x5@8")
    #expect(conflictEntry.valueCheckOutcome == "Expected '205x3@9', found '185x5@8'.")
}

/// The same two writes with no overlap to flush early: the second write's target is a different
/// cell, so planning it fails straight to a conflict without touching the batch.
@MainActor
@Test func planningFailureOnAFreshTargetConflictsWithoutWritingTheBatchEarly() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    let mismatched = replanPendingWrite(createdAt: 2, valueToWrite: "225x3@9", expectedCurrentValue: "205x3@9")
    mismatched.exerciseName = "Bench Press"
    ctx.insert(mismatched)
    try ctx.save()
    let client = ScriptedSnapshotClient(
        grids: [
            gridFromA1(
                [
                    "C12": "Day 1", "S12": "Day 2",
                    "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                    "C15": "Squat", "D15": "1",
                    "C17": "Bench Press", "D17": "1"
                ],
                rows: 24,
                cols: 30
            )
        ]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.fetchCount == 1)
    #expect(client.updates.map(\.range) == ["'Block 27'!K15"])
    #expect(client.updates.map(\.values) == [[["185x5@8"]]])
    #expect(sync.outcome == .writesRefused(["Bench Press: Expected '205x3@9', found ''"]))
}
