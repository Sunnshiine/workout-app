import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private final class FlushStubClient: SheetsClient, @unchecked Sendable {
    var grid: SheetGrid
    var fetches: [String] = []
    var updates: [(String, [[String]])] = []
    var shouldThrowOffline = false

    init(grid: SheetGrid) {
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }
    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        if shouldThrowOffline { throw URLError(.notConnectedToInternet) }
        fetches.append(tabName)
        return grid
    }
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        updates.append((range, values))
    }
}

private final class ControlledFlushClient: SheetsClient, @unchecked Sendable {
    private let coordinator = ControlledFlushCoordinator()

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }

    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        try await coordinator.fetchTab()
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
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
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
    #expect(sync.state == .idle)
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
    #expect(client.updates.map(\.0) == ["'Block 27'!K16", "'Block 27'!K16"])
    #expect(client.updates.map(\.1) == [[["185x5@8"]], [["185x6@8"]]])
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.state == .idle)
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

    #expect(client.updates.map(\.0) == ["'Block 27'!K16"])
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.state == .idle)
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
                "C15": "Squat", "D15": "1", "K16": "coach edited"
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
    #expect(sync.state.isConflict)
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
    #expect(sync.state == .idle)
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
                "C15": "Squat", "D15": "1", "K16": "coach edited"
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
    private var fetchContinuation: CheckedContinuation<SheetGrid, Error>?
    private var hasFetchStarted = false
    private var fetchWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var updates: [(String, [[String]])] = []

    func fetchTab() async throws -> SheetGrid {
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
        fetchContinuation?.resume(returning: grid)
        fetchContinuation = nil
    }

    func recordUpdate(range: String, values: [[String]]) {
        updates.append((range, values))
    }
}

extension SyncCoordinator.State {
    fileprivate var isConflict: Bool {
        if case .conflict = self { return true }
        return false
    }
}
