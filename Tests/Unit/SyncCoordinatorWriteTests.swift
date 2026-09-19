import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private final class FlushStubClient: SheetsClient, @unchecked Sendable {
    var grid: SheetGrid
    var fetches: [String] = []
    var updates: [(String, [[String]])] = []
    var shouldThrowOffline = false
    var shouldFailUpdates = false

    init(grid: SheetGrid) {
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }
    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        if shouldThrowOffline { throw URLError(.notConnectedToInternet) }
        fetches.append(tabName)
        return SheetSnapshot(values: grid)
    }
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        if shouldFailUpdates { throw URLError(.timedOut) }
        updates.append((range, values))
    }

    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
        if shouldFailUpdates { throw URLError(.timedOut) }
        self.updates.append(contentsOf: updates.map { ($0.range, $0.values) })
    }
}

private final class PlanningIndexBuildCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0

    func build(from grid: SheetGrid) -> SheetLayout {
        lock.lock()
        count += 1
        lock.unlock()
        return SheetLayoutInterpreter().interpret(grid)
    }
}

private final class ControlledFlushClient: SheetsClient, @unchecked Sendable {
    private let coordinator = ControlledFlushCoordinator()

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        try await coordinator.fetchTabSnapshot()
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        await coordinator.recordUpdate(range: range, values: values)
    }

    func waitForFetch() async {
        await coordinator.waitForFetch()
    }

    func completeFetch(with grid: SheetGrid) async {
        await coordinator.completeFetch(with: grid)
    }

    func updates() async -> [(String, [[String]])] {
        await coordinator.updates
    }
}

@MainActor
private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func pendingWrite(
    createdAt: TimeInterval? = nil,
    exerciseName: String = "Squat",
    setIndex: Int = 0,
    column: PendingWriteColumn = .notes,
    valueToWrite: String? = "185x5@8",
    expectedCurrentValue: String = ""
) -> PendingWrite {
    PendingWrite(
        createdAt: createdAt.map(Date.init(timeIntervalSince1970:)) ?? Date(),
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: exerciseName,
        setIndex: setIndex,
        column: column,
        operation: .upsert,
        valueToWrite: valueToWrite,
        expectedCurrentValue: expectedCurrentValue
    )
}

@MainActor
@Test func discardPendingWritesFailsWhileFlushIsInFlight() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(
        PendingWrite(
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
    )
    try ctx.save()
    let client = ControlledFlushClient()
    let sync = SyncCoordinator(client: client, context: ctx)

    let flushTask = Task { await sync.flushPending(spreadsheetId: "old-sheet") }
    await client.waitForFetch()

    await #expect(throws: (any Error).self) {
        try await sync.discardPendingWrites()
    }

    await client.completeFetch(
        with: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1"
            ],
            rows: 24,
            cols: 30
        )
    )

    await flushTask.value

    #expect(await client.updates().count == 1)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.outcome == .clear)
}

@MainActor
@Test func flushReusesTabSnapshotForChainedWritesToSameSet() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(
        PendingWrite(
            createdAt: Date(timeIntervalSince1970: 1),
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
    )
    ctx.insert(
        PendingWrite(
            createdAt: Date(timeIntervalSince1970: 2),
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Squat",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "185x6@8",
            expectedCurrentValue: "185x5@8"
        )
    )
    try ctx.save()
    let client = FlushStubClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1"
            ],
            rows: 24,
            cols: 30
        )
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.fetches == ["Block 27"])
    #expect(client.updates.map(\.0) == ["'Block 27'!K15", "'Block 27'!K15"])
    #expect(client.updates.map(\.1) == [[["185x5@8"]], [["185x6@8"]]])
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.outcome == .clear)
}

@MainActor
@Test func flushBuildsPlanningIndexOnceForMultipleWritesToFetchedSnapshot() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(pendingWrite(createdAt: 1))
    ctx.insert(pendingWrite(createdAt: 2, setIndex: 1, valueToWrite: "195x5@8"))
    ctx.insert(pendingWrite(createdAt: 3, setIndex: 1, column: .lastSetRPE, valueToWrite: "8"))
    try ctx.save()
    let client = FlushStubClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
                "C15": "Squat", "D15": "2"
            ],
            rows: 24,
            cols: 30
        )
    )
    let counter = PlanningIndexBuildCounter()
    let planner = SheetWritePlanner(layoutBuilder: counter.build(from:))
    let sync = SyncCoordinator(client: client, context: ctx, sheetWritePlanner: planner)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.fetches == ["Block 27"])
    #expect(counter.count == 1)
    #expect(client.updates.map(\.0) == ["'Block 27'!K15", "'Block 27'!K15", "'Block 27'!I15"])
    #expect(client.updates.map(\.1) == [[["185x5@8"]], [["185x5@8, 195x5@8"]], [["8"]]])
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
}

@MainActor
@Test func flushPendingWritesDeletesSuccessfulQueueItem() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(
        PendingWrite(
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
    )
    try ctx.save()
    let client = FlushStubClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1"
            ],
            rows: 24,
            cols: 30
        )
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updates.map(\.0) == ["'Block 27'!K15"])
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.outcome == .clear)
}

@MainActor
@Test func flushMarksConflictWhenVerificationFails() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(
        PendingWrite(
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
    )
    try ctx.save()
    let client = FlushStubClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1", "K15": "Coach note", "K16": "coach edited"
            ],
            rows: 24,
            cols: 30
        )
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.fetches == ["Block 27"])
    let write = try #require(try ctx.fetch(FetchDescriptor<PendingWrite>()).first)
    #expect(write.status == .conflict)
    #expect(client.updates.isEmpty)
    #expect(sync.outcome.isWritesRefused)
}

@MainActor
@Test func flushMarksOnlyUnexpectedWriteAsConflictWithoutOverwritingSheet() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(pendingWrite(createdAt: 1))
    ctx.insert(pendingWrite(createdAt: 2, exerciseName: "Bench Press", valueToWrite: "135x5@7"))
    try ctx.save()
    let client = FlushStubClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1",
                "C17": "Bench Press", "D17": "1", "K17": "Coach note", "K18": "coach edited"
            ],
            rows: 24,
            cols: 30
        )
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updates.map(\.0) == ["'Block 27'!K15"])
    #expect(client.updates.map(\.1) == [[["185x5@8"]]])
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.count == 1)
    let conflict = try #require(writes.first)
    #expect(conflict.exerciseName == "Bench Press")
    #expect(conflict.status == .conflict)
    #expect(sync.outcome.isWritesRefused)
}

@MainActor
@Test func discardPendingWritesRemovesQueuedAndConflictedWrites() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(
        PendingWrite(
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
    )
    let conflicted = PendingWrite(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Bench Press",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "135x5@7",
        expectedCurrentValue: ""
    )
    conflicted.markConflict("coach edited")
    ctx.insert(conflicted)
    try ctx.save()
    let sync = SyncCoordinator(client: FlushStubClient(grid: []), context: ctx)

    #expect(try sync.hasPendingWrites() == true)

    try await sync.discardPendingWrites()

    #expect(try sync.hasPendingWrites() == false)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.outcome == .clear)
}

@MainActor
@Test func syncOverlaysStillPendingWritesOntoFreshBlock() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(
        PendingWrite(
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
    )
    try ctx.save()
    let client = FlushStubClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1", "K15": "Coach note", "K16": "coach edited"
            ],
            rows: 24,
            cols: 30
        )
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.sync(spreadsheetId: "sid")

    let block = try #require(try ctx.fetch(FetchDescriptor<Block>()).first)
    let week = try #require(block.weeks.first { $0.number == 1 })
    let session = try #require(week.sessions.first { $0.dayNumber == 1 })
    let exercise = try #require(session.exercises.first { $0.name == "Squat" })
    let set = try #require(exercise.sets.first { $0.index == 0 })
    #expect(set.state == .logged)
    #expect(set.setLog?.formatted == "185x5@8")
}

private actor ControlledFlushCoordinator {
    private var fetchContinuation: CheckedContinuation<SheetSnapshot, Error>?
    private var hasFetchStarted = false
    private var fetchWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var updates: [(String, [[String]])] = []

    func fetchTabSnapshot() async throws -> SheetSnapshot {
        hasFetchStarted = true
        for waiter in fetchWaiters {
            waiter.resume()
        }
        fetchWaiters = []

        return try await withCheckedThrowingContinuation { continuation in
            fetchContinuation = continuation
        }
    }

    func waitForFetch() async {
        if hasFetchStarted { return }
        await withCheckedContinuation { continuation in
            fetchWaiters.append(continuation)
        }
    }

    func completeFetch(with grid: SheetGrid) {
        fetchContinuation?.resume(returning: SheetSnapshot(values: grid))
        fetchContinuation = nil
    }

    func recordUpdate(range: String, values: [[String]]) {
        updates.append((range, values))
    }
}

extension SyncOutcome {
    fileprivate var isWritesRefused: Bool {
        if case .writesRefused = self { return true }
        return false
    }
}

@MainActor
@Test func flushRecordsOneRetryAndStopsWhenTheSnapshotFetchFails() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(pendingWrite(createdAt: 1))
    ctx.insert(pendingWrite(createdAt: 2, setIndex: 1, valueToWrite: "195x5@8"))
    try ctx.save()
    let client = FlushStubClient(grid: overlayGrid(notes: ""))
    client.shouldThrowOffline = true
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(sync.outcome == .writesQueued(2))
    #expect(client.updates.isEmpty)
    #expect(writes.count == 2)
    #expect(writes.allSatisfy { $0.status == .pending })
    #expect(writes.sorted { $0.createdAt < $1.createdAt }.map(\.retryCount) == [1, 0])
}

@MainActor
@Test func syncOverlaysAQueuedDeleteAsAPendingSet() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(queuedSquatNotesWrite(setIndex: 0, operation: .delete, value: nil))
    try ctx.save()
    let sync = SyncCoordinator(client: FlushStubClient(grid: overlayGrid(notes: "185x5@8")), context: ctx)

    await sync.sync(spreadsheetId: "sid")

    let set = try #require(try overlaidSquatSet(index: 0, in: ctx))
    #expect(set.state == .pending)
    #expect(set.setLog == nil)
    #expect(set.loggedAt == nil)
}

@MainActor
@Test func syncOverlaysAQueuedSkipTokenAsASkippedSet() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(queuedSquatNotesWrite(setIndex: 0, operation: .upsert, value: "skip"))
    try ctx.save()
    let sync = SyncCoordinator(client: FlushStubClient(grid: overlayGrid(notes: "185x5@8")), context: ctx)

    await sync.sync(spreadsheetId: "sid")

    let set = try #require(try overlaidSquatSet(index: 0, in: ctx))
    #expect(set.state == .skipped)
    #expect(set.setLog == nil)
    #expect(set.loggedAt == nil)
}

@MainActor
@Test func syncOverlaysAStillPendingSetLogOverAnUnstructuredSetLogWithoutKeepingTheFreeText() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let write = PendingWrite(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: "felt heavy"
    )
    ctx.insert(write)
    try ctx.save()
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "K15": "Coach note", "K16": "felt heavy"
        ],
        rows: 24,
        cols: 30
    )
    let client = FlushStubClient(grid: grid)
    client.shouldFailUpdates = true
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.sync(spreadsheetId: "sid")

    let set = try #require(try overlaidSquatSet(index: 0, in: ctx))
    #expect(write.status == .pending)
    #expect(set.state == .logged)
    #expect(set.setLog?.formatted == "185x5@8")
    #expect(set.unstructuredSetLog == nil)
}

@MainActor
@Test func syncIgnoresAQueuedWriteWhoseSetIsAbsentFromTheFreshBlock() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(queuedSquatNotesWrite(setIndex: 9, operation: .delete, value: nil))
    try ctx.save()
    let sync = SyncCoordinator(client: FlushStubClient(grid: overlayGrid(notes: "185x5@8")), context: ctx)

    await sync.sync(spreadsheetId: "sid")

    let set = try #require(try overlaidSquatSet(index: 0, in: ctx))
    #expect(set.state == .logged)
    #expect(set.setLog?.formatted == "185x5@8")
}

/// The mismatched `expectedCurrentValue` makes the flush record a conflict, which is what leaves the
/// write queued for the overlay to replay.
@MainActor
private func queuedSquatNotesWrite(
    setIndex: Int,
    operation: PendingWriteOperation,
    value: String?
) -> PendingWrite {
    PendingWrite(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: setIndex,
        column: .notes,
        operation: operation,
        valueToWrite: value,
        expectedCurrentValue: "a value the sheet does not hold"
    )
}

private func overlayGrid(notes: String) -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "K15": notes
        ],
        rows: 24,
        cols: 30
    )
}

@MainActor
private func overlaidSquatSet(index: Int, in ctx: ModelContext) throws -> ExerciseSet? {
    try ctx.fetch(FetchDescriptor<Block>()).first?
        .weeks.first { $0.number == 1 }?
        .sessions.first { $0.dayNumber == 1 }?
        .exercises.first { $0.name == "Squat" }?
        .sets.first { $0.index == index }
}
