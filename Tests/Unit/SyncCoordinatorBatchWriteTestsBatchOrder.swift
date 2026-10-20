import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func flushBatchesIndependentNonOverlappingPendingWrites() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, setIndex: 0, valueToWrite: "185x5@8"))
    ctx.insert(batchPendingWrite(createdAt: 2, setIndex: 1, column: .lastSetRPE, valueToWrite: "8"))
    try ctx.save()
    let client = BatchFlushStubClient(grid: twoSetGrid())
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.fetches == ["Block 27"])
    #expect(client.updateRequestCount == 1)
    #expect(
        client.writes == [
            SheetCellWrite(tabName: "Block 27", a1: "K15", value: "185x5@8"),
            SheetCellWrite(tabName: "Block 27", a1: "I15", value: "8")
        ]
    )
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.outcome == .clear)
}

@MainActor
@Test func flushSplitsOverlappingTargetRangesIntoOrderedBatches() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, valueToWrite: "185x5@8"))
    ctx.insert(batchPendingWrite(createdAt: 2, valueToWrite: "185x6@8", expectedCurrentValue: "185x5@8"))
    try ctx.save()
    let client = BatchFlushStubClient(grid: oneSetGrid())
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updateRequestCount == 2)
    #expect(
        client.writes == [
            SheetCellWrite(tabName: "Block 27", a1: "K15", value: "185x5@8"),
            SheetCellWrite(tabName: "Block 27", a1: "K15", value: "185x6@8")
        ]
    )
    #expect(client.grid.cell(row: 14, col: 10) == "185x6@8")
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.outcome == .clear)
}

@MainActor
@Test func flushSplitsExpectedCurrentValueDependenciesIntoOrderedBatches() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, valueToWrite: "185x5@8"))
    ctx.insert(
        batchPendingWrite(
            createdAt: 2,
            operation: .delete,
            valueToWrite: nil,
            expectedCurrentValue: "185x5@8"
        )
    )
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: coachNoteHiddenContinuationGrid(),
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updateRequestCount == 2)
    #expect(
        client.writes == [
            SheetCellWrite(tabName: "Block 27", a1: "K17", value: "185x5@8"),
            SheetCellWrite(tabName: "Block 27", a1: "K17", value: "")
        ]
    )
    #expect(client.grid.cell(row: 15, col: 10) == "")
    #expect(client.grid.cell(row: 16, col: 10) == "")
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
}

@MainActor
@Test func flushExcludesConflictsFromBatchWithoutBlockingCompatibleWrites() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, exerciseName: "Squat", valueToWrite: "185x5@8"))
    ctx.insert(batchPendingWrite(createdAt: 2, exerciseName: "Bench Press", valueToWrite: "135x5@7"))
    ctx.insert(batchPendingWrite(createdAt: 3, exerciseName: "Deadlift", valueToWrite: "275x5@8"))
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: multiExerciseConflictGrid(),
        rowVisibility: [17: SheetRowVisibility(hiddenByUser: true)]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updateRequestCount == 1)
    #expect(
        client.writes.map(\.target) == [SheetWriteTarget(tabName: "Block 27", a1: "K15"), SheetWriteTarget(tabName: "Block 27", a1: "K19")]
    )
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.count == 1)
    let conflict = try #require(writes.first)
    #expect(conflict.exercise == .first("Bench Press"))
    #expect(conflict.status == .conflict)
    #expect(refusedWrites(sync.outcome) != nil)
}

@MainActor
@Test func orderPendingWritesForFlushPutsASetLogBeforeItsLastSetRPEMirror() throws {
    let container = try makeBatchContainer()
    let sync = SyncCoordinator(client: BatchFlushStubClient(grid: twoSetGrid()), context: container.mainContext)
    let mirror = batchPendingWrite(createdAt: 2, setIndex: 1, column: .lastSetRPE, valueToWrite: "9")
    let setLog = batchPendingWrite(createdAt: 1, setIndex: 1, valueToWrite: "195x5@9")

    let ordered = sync.orderPendingWritesForFlush([mirror, setLog])

    #expect(ordered.map(\.column) == [.notes, .lastSetRPE])
}

@MainActor
@Test func orderPendingWritesForFlushPutsASetLogBeforeAMirrorQueuedAheadOfIt() throws {
    let container = try makeBatchContainer()
    let sync = SyncCoordinator(client: BatchFlushStubClient(grid: twoSetGrid()), context: container.mainContext)
    let mirror = batchPendingWrite(createdAt: 1, setIndex: 1, column: .lastSetRPE, valueToWrite: "9")
    let setLog = batchPendingWrite(createdAt: 2, setIndex: 1, valueToWrite: "195x5@9")

    let ordered = sync.orderPendingWritesForFlush([mirror, setLog])

    #expect(ordered.map(\.column) == [.notes, .lastSetRPE])
}

@MainActor
@Test func orderPendingWritesForFlushKeepsWritesForDifferentSetsInQueuedOrder() throws {
    let container = try makeBatchContainer()
    let sync = SyncCoordinator(client: BatchFlushStubClient(grid: twoSetGrid()), context: container.mainContext)
    let secondSet = batchPendingWrite(createdAt: 2, setIndex: 1, column: .lastSetRPE, valueToWrite: "9")
    let firstSet = batchPendingWrite(createdAt: 1, setIndex: 0, valueToWrite: "185x5@8")

    let ordered = sync.orderPendingWritesForFlush([secondSet, firstSet])

    #expect(ordered.map(\.setIndex) == [0, 1])
}

private func twoSetGrid(notesOnly: Bool = false, firstSetLog: String? = nil) -> SheetGrid {
    var cells = [
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
        "C15": "Squat", "D15": "2"
    ]
    if let firstSetLog {
        cells["K15"] = firstSetLog
    }
    if !notesOnly {
        cells["I14"] = "Last set RPE"
    }
    return gridFromA1(cells, rows: 24, cols: 30)
}
