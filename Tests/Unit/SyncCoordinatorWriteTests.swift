import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private final class FlushStubClient: SheetsClient, @unchecked Sendable {
    var grid: SheetGrid
    var fetches: [String] = []
    var updates: [(String, [[String]])] = []
    var shouldThrowOffline = false
    var offlineFetches = 0
    var shouldFailUpdates = false

    init(grid: SheetGrid) {
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }
    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        if shouldThrowOffline { throw URLError(.notConnectedToInternet) }
        if offlineFetches > 0 {
            offlineFetches -= 1
            throw URLError(.notConnectedToInternet)
        }
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

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
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
    createdAt: TimeInterval,
    day: Int = 1,
    dayNumbering: DayNumbering = .headerRank,
    exerciseName: String = "Squat",
    setIndex: Int = 0,
    column: PendingWriteColumn = .notes,
    valueToWrite: String? = "185x5@8",
    expectedCurrentValue: String = ""
) -> PendingWrite {
    PendingWrite(
        createdAt: Date(timeIntervalSince1970: createdAt),
        blockTab: "Block 27",
        week: 1,
        day: day,
        dayNumbering: dayNumbering,
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
    let planner = SheetWritePlanner(onLayoutBuilt: counter.increment)
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
@Test func flushRefusesAQueuedWriteWhoseDayHeaderWasCleared() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(pendingWrite(createdAt: 1, dayNumbering: .headerNumber))
    try ctx.save()
    let client = FlushStubClient(
        grid: gridFromA1(
            [
                "S12": "Day 2",
                "D14": "Sets", "K14": "Notes", "C15": "Squat", "D15": "1",
                "T14": "Sets", "AA14": "Notes", "S15": "Squat", "T15": "1"
            ],
            rows: 24,
            cols: 40
        )
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updates.isEmpty)
    #expect(sync.outcome == .writesRefused(["Squat: Day 1 was not found in the sheet"]))
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.map(\.status) == [.conflict])
    #expect(writes.map(\.lastError) == ["Day 1 was not found in the sheet"])
    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    #expect(entries.map(\.selectedA1Target) == [nil])
    #expect(entries.map(\.finalStatus) == [.conflict])
    #expect(entries.map(\.rowScanDetails) == ["No row selected: Week 1, Day 1 was not found."])
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

private let dayHeadersChangedMeaning = "The sheet's Day headers changed meaning since this Set was logged. Log it again."

/// Column groups 16 wide from C, headed by `headers` in row 12 (nil leaves a group unheaded). Each
/// holds a three-Set Squat in row 15 whose Notes cell is K15, AA15, or AQ15.
private func upgradeGrid(_ headers: [String?], notes: [String: String] = [:]) -> SheetGrid {
    var cells = notes
    for ((name, sets, notesColumn), header) in zip([("C", "D", "K"), ("S", "T", "AA"), ("AI", "AJ", "AQ")], headers) {
        cells["\(name)12"] = header
        cells["\(sets)14"] = "Sets"
        cells["\(notesColumn)14"] = "Notes"
        cells["\(name)15"] = "Squat"
        cells["\(sets)15"] = "3"
    }
    return gridFromA1(cells, rows: 24, cols: 52)
}

/// Every logged Squat Set in the cached Block, as `w1d<day> s<index>=<Set Log>`.
@MainActor
private func loggedSquatSets(in ctx: ModelContext) throws -> [String] {
    let week = try ctx.fetch(FetchDescriptor<Block>()).first?.weeks.first { $0.number == 1 }
    var logged: [String] = []
    for session in (week?.sessions ?? []).sorted(by: { $0.dayNumber < $1.dayNumber }) {
        let sets: [ExerciseSet] = session.exercises.filter { $0.name == "Squat" }.flatMap(\.sets)
        for set in sets.sorted(by: { $0.index < $1.index }) where set.state == .logged {
            logged.append("w1d\(session.dayNumber) s\(set.index)=\(set.setLog?.formatted ?? "")")
        }
    }
    return logged
}

private struct HeaderRankRefusal: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let headers: [String?]
    let notes: [String: String]
    let day: Int
    let setIndex: Int
    let lastError: String
    let rowScan: String
}

@MainActor
@Test(arguments: [
    HeaderRankRefusal(
        testDescription: "U2 swapped, K15 logged",
        headers: ["Day 2", "Day 1"],
        notes: ["K15": "185x5@8"],
        day: 1,
        setIndex: 1,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 1 was queued by header rank, "
            + "and the Week's Day header at rank 1 does not read Day 1."
    ),
    HeaderRankRefusal(
        testDescription: "U2q swapped",
        headers: ["Day 2", "Day 1"],
        notes: [:],
        day: 1,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 1 was queued by header rank, "
            + "and the Week's Day header at rank 1 does not read Day 1."
    ),
    HeaderRankRefusal(
        testDescription: "U3 Day 1 cleared, AQ15 logged",
        headers: [nil, "Day 2", "Day 3"],
        notes: ["AQ15": "185x5@8"],
        day: 2,
        setIndex: 1,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and the Week's Day header at rank 2 does not read Day 2."
    ),
    HeaderRankRefusal(
        testDescription: "U3q Day 1 cleared",
        headers: [nil, "Day 2", "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and the Week's Day header at rank 2 does not read Day 2."
    ),
    HeaderRankRefusal(
        testDescription: "U3r Day 1 cleared, rank 1",
        headers: [nil, "Day 2", "Day 3"],
        notes: [:],
        day: 1,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 1 was queued by header rank, "
            + "and the Week's Day header at rank 1 does not read Day 1."
    ),
    HeaderRankRefusal(
        testDescription: "U4 middle cleared",
        headers: ["Day 1", nil, "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and the Week's Day header at rank 2 does not read Day 2."
    ),
    HeaderRankRefusal(
        testDescription: "U5 gap",
        headers: ["Day 1", "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and the Week's Day header at rank 2 does not read Day 2."
    ),
    HeaderRankRefusal(
        testDescription: "Day 8 at rank 3",
        headers: ["Day 1", "Day 2", "Day 8"],
        notes: [:],
        day: 3,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 3 was queued by header rank, "
            + "and the Week's Day header at rank 3 does not read Day 3."
    ),
    HeaderRankRefusal(
        testDescription: "Day 1 repeated, rank 1",
        headers: ["Day 1", "Day 1", "Day 3"],
        notes: [:],
        day: 1,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 1 was queued by header rank, "
            + "and the Week's Day header at rank 1 does not read Day 1."
    ),
    HeaderRankRefusal(
        testDescription: "Day 1 repeated, rank 2",
        headers: ["Day 1", "Day 1", "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and the Week's Day header at rank 2 does not read Day 2."
    ),
    HeaderRankRefusal(
        testDescription: "rank and number both name no Day",
        headers: ["Day 1", "Day 2", "Day 3"],
        notes: [:],
        day: 4,
        setIndex: 0,
        lastError: "Day 4 was not found in the sheet",
        rowScan: "No row selected: Week 1, Day 4 was not found."
    )
])
private func flushRefusesAWriteQueuedByHeaderRankWhereItsRankAndNumberDisagree(
    _ refusal: HeaderRankRefusal
) async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(
        pendingWrite(
            createdAt: 1,
            day: refusal.day,
            dayNumbering: .headerRank,
            setIndex: refusal.setIndex,
            valueToWrite: "190x5@8"
        )
    )
    try ctx.save()
    let client = FlushStubClient(grid: upgradeGrid(refusal.headers, notes: refusal.notes))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updates.isEmpty)
    #expect(sync.outcome == .writesRefused(["Squat: \(refusal.lastError)"]))
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.map(\.status) == [.conflict])
    #expect(writes.map(\.lastError) == [refusal.lastError])
    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    #expect(entries.map(\.finalStatus) == [.conflict])
    #expect(entries.map(\.selectedA1Target) == [nil])
    #expect(entries.map(\.rowScanDetails) == [refusal.rowScan])
}

private struct QueuedWriteLanding: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let headers: [String?]
    let notes: [String: String]
    let day: Int
    let dayNumbering: DayNumbering
    let setIndex: Int
    let range: String
    let value: String
}

@MainActor
@Test(arguments: [
    QueuedWriteLanding(
        testDescription: "U1 headed in order",
        headers: ["Day 1", "Day 2", "Day 3"],
        notes: ["AA15": "185x5@8"],
        day: 2,
        dayNumbering: .headerRank,
        setIndex: 1,
        range: "'Block 27'!AA15",
        value: "185x5@8, 190x5@8"
    ),
    QueuedWriteLanding(
        testDescription: "U6 Day 1 repeated, rank 3",
        headers: ["Day 1", "Day 1", "Day 3"],
        notes: [:],
        day: 3,
        dayNumbering: .headerRank,
        setIndex: 0,
        range: "'Block 27'!AQ15",
        value: "190x5@8"
    ),
    QueuedWriteLanding(
        testDescription: "Day 8 at rank 3, rank 2",
        headers: ["Day 1", "Day 2", "Day 8"],
        notes: [:],
        day: 2,
        dayNumbering: .headerRank,
        setIndex: 0,
        range: "'Block 27'!AA15",
        value: "190x5@8"
    ),
    QueuedWriteLanding(
        testDescription: "a header-number write on swapped headers",
        headers: ["Day 2", "Day 1"],
        notes: [:],
        day: 1,
        dayNumbering: .headerNumber,
        setIndex: 0,
        range: "'Block 27'!AA15",
        value: "190x5@8"
    )
])
private func flushLandsAQueuedWriteWhereItsDayNamesOneSession(_ landing: QueuedWriteLanding) async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(
        pendingWrite(
            createdAt: 1,
            day: landing.day,
            dayNumbering: landing.dayNumbering,
            setIndex: landing.setIndex,
            valueToWrite: "190x5@8"
        )
    )
    try ctx.save()
    let client = FlushStubClient(grid: upgradeGrid(landing.headers, notes: landing.notes))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updates.map(\.0) == [landing.range])
    #expect(client.updates.map(\.1) == [[[landing.value]]])
    #expect(sync.outcome == .clear)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
}

@MainActor
@Test func aRefusedHeaderRankWriteShowsOnNeitherSessionOnThisOrALaterSync() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(pendingWrite(createdAt: 1, dayNumbering: .headerRank, setIndex: 1, valueToWrite: "190x5@8"))
    try ctx.save()
    let client = FlushStubClient(grid: upgradeGrid(["Day 2", "Day 1"], notes: ["K15": "185x5@8"]))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.sync(spreadsheetId: "sid")

    #expect(sync.outcome == .writesRefused(["Squat: \(dayHeadersChangedMeaning)"]))
    let loggedAfterTheRefusingSync = try loggedSquatSets(in: ctx)
    #expect(loggedAfterTheRefusingSync == ["w1d2 s0=185x5@8"])

    await sync.sync(spreadsheetId: "sid")

    #expect(sync.outcome == .clear)
    #expect(client.updates.isEmpty)
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.map(\.status) == [.conflict])
    #expect(writes.map(\.lastError) == [dayHeadersChangedMeaning])
    let loggedAfterALaterSync = try loggedSquatSets(in: ctx)
    #expect(loggedAfterALaterSync == ["w1d2 s0=185x5@8"])
}

@MainActor
@Test(arguments: [
    (["Day 2", "Day 1"], [String]()),
    (["Day 1", "Day 2"], ["w1d1 s0=190x5@8"])
])
func aHeaderRankWriteTheFlushStoppedBeforeShowsOnlyWhereItsRankAndNumberAgree(
    headers: [String?],
    logged: [String]
) async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let write = pendingWrite(createdAt: 1, dayNumbering: .headerRank, valueToWrite: "190x5@8")
    ctx.insert(write)
    try ctx.save()
    let client = FlushStubClient(grid: upgradeGrid(headers))
    client.offlineFetches = 1
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.sync(spreadsheetId: "sid")

    #expect(sync.outcome == .clear)
    #expect(client.updates.isEmpty)
    #expect(write.status == .pending)
    #expect(write.retryCount == 1)
    let overlaid = try loggedSquatSets(in: ctx)
    #expect(overlaid == logged)
}

@MainActor
@Test func aSetLoggedOnABlockCachedBeforeHeaderNumberingIsRefusedOnceTheHeadersReadSwapped() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let client = FlushStubClient(grid: upgradeGrid(["Day 1", "Day 2"]))
    let sync = SyncCoordinator(client: client, context: ctx)
    await sync.sync(spreadsheetId: "sid")
    try #require(try ctx.fetch(FetchDescriptor<Block>()).first).dayNumberingRaw = nil
    try ctx.save()
    let store = WorkoutStore(context: ctx, defaults: .inMemory())
    store.reload()
    let set = try #require(
        store.block?.weeks.first?.sessions.first { $0.dayNumber == 1 }?.exercises.first?.sets.first { $0.index == 0 }
    )
    try store.log(set, as: SetLog(weight: .pounds(190), reps: 5, rpe: .eight))
    client.grid = upgradeGrid(["Day 2", "Day 1"])

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updates.isEmpty)
    #expect(sync.outcome == .writesRefused(["Squat: \(dayHeadersChangedMeaning)"]))
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.map(\.status) == [.conflict])
    #expect(writes.map(\.lastError) == [dayHeadersChangedMeaning])
}
