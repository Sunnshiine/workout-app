import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

/// A Sheet that keeps what the flush writes to it, so a test can read the literal cell value the
/// coach would see. `remoteEdits` stands in for someone else typing into the Sheet while the flush
/// is mid-air: the entry keyed by a fetch number lands just before that fetch answers.
private final class LiveSheetClient: SheetsClient, @unchecked Sendable {
    private var grid: SheetGrid
    private let remoteEdits: [Int: [String: String]]
    private(set) var fetchCount = 0

    init(grid: SheetGrid, remoteEdits: [Int: [String: String]] = [:]) {
        self.grid = grid
        self.remoteEdits = remoteEdits
    }

    func cell(_ a1: String) -> String {
        let index = a1CellIndex(a1)!
        return grid.cell(row: index.row, col: index.col)
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        fetchCount += 1
        for (a1, value) in remoteEdits[fetchCount] ?? [:] {
            write([[value]], to: a1)
        }
        return SheetSnapshot(values: grid)
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        write(values, to: splitA1Range(range)!.reference)
    }

    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
        for update in updates {
            try await updateCells(spreadsheetId: spreadsheetId, range: update.range, values: update.values)
        }
    }

    private func write(_ values: [[String]], to a1: String) {
        let index = a1CellIndex(a1)!
        grid.write(values, atRow: index.row, col: index.col)
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

private func squatOneSetGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1"
        ],
        rows: 24,
        cols: 30
    )
}

/// Two queued Notes writes for the same Set resolve to the same cell, so planning the second one
/// against the batch's in-memory snapshot fails its expected-current-value check. The flush writes
/// the batch out early and re-plans the second write.
///
/// The coach edits K15 to `205x3@9` while the flush is mid-air, which is exactly what the second
/// write expects, so the re-plan has to read the Sheet again rather than the value the batch
/// predicted. The athlete's `205x3@10` lands.
@MainActor
@Test func replanningAnAlreadyBatchedTargetReadsTheSheetAgainAndLandsTheWrite() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = LiveSheetClient(grid: squatOneSetGrid(), remoteEdits: [2: ["K15": "205x3@9"]])
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K15") == "205x3@10")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .clear)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    #expect(entries.map(\.finalStatus) == [.succeeded, .succeeded])
    #expect(entries.allSatisfy { $0.selectedA1Target == "'Block 27'!K15" })
}

/// The same re-plan when the coach's mid-air edit is not what the write expects. The re-read decides
/// the conflict against what the Sheet really holds, and the coach's value stays in the cell.
@MainActor
@Test func replanningAnAlreadyBatchedTargetConflictsAgainstTheValueTheSheetReallyHolds() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = LiveSheetClient(grid: squatOneSetGrid(), remoteEdits: [2: ["K15": "300x1@10"]])
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K15") == "300x1@10")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .writesRefused(["Squat: Expected '205x3@9', found '300x1@10'"]))

    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(remaining.count == 1)
    #expect(remaining.first?.status == .conflict)
    #expect(remaining.first?.valueToWrite == "205x3@10")

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    #expect(entries.map(\.finalStatus).sorted { $0.rawValue < $1.rawValue } == [.conflict, .succeeded])
    let conflictEntry = try #require(entries.first { $0.finalStatus == .conflict })
    #expect(conflictEntry.selectedA1Target == "'Block 27'!K15")
    #expect(conflictEntry.currentValue == "300x1@10")
    #expect(conflictEntry.valueCheckOutcome == "Expected '205x3@9', found '300x1@10'.")
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
    let client = LiveSheetClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1",
                "C17": "Bench Press", "D17": "1"
            ],
            rows: 24,
            cols: 30
        )
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K15") == "185x5@8")
    #expect(client.cell("K17") == "")
    #expect(client.fetchCount == 1)
    #expect(sync.outcome == .writesRefused(["Bench Press: Expected '205x3@9', found ''"]))
}
