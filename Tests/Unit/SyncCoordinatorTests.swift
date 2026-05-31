import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private struct StubClient: SheetsClient {
    var titles: [String]
    var grid: SheetGrid
    var failOffline = false
    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        if failOffline { throw URLError(.notConnectedToInternet) }
        return titles
    }
    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid { grid }
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}

private final class BackfillStubClient: SheetsClient, @unchecked Sendable {
    let titles: [String]
    let grids: [String: SheetGrid]
    let failingTabs: Set<String>
    let suspendedTabs: Set<String>
    let recorder: FetchRecorder

    init(
        titles: [String],
        grids: [String: SheetGrid],
        failingTabs: Set<String> = [],
        suspendedTabs: Set<String> = [],
        recorder: FetchRecorder = FetchRecorder()
    ) {
        self.titles = titles
        self.grids = grids
        self.failingTabs = failingTabs
        self.suspendedTabs = suspendedTabs
        self.recorder = recorder
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { titles }

    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        await recorder.record(tabName)
        if failingTabs.contains(tabName) { throw URLError(.notConnectedToInternet) }
        if suspendedTabs.contains(tabName) {
            await recorder.waitForRelease()
        }
        return grids[tabName] ?? []
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}

private actor FetchRecorder {
    private var fetchedTabs: [String] = []
    private var syncReturned = false
    private var released = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func record(_ tab: String) {
        fetchedTabs.append(tab)
    }

    func tabs() -> [String] {
        fetchedTabs
    }

    func markSyncReturned() {
        syncReturned = true
    }

    func didSyncReturn() -> Bool {
        syncReturned
    }

    func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class BackfillCompletionProbe: LastPerformedBackfillObserving {
    private var didFinish = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func lastPerformedBackfillDidFinish() {
        didFinish = true
        let waitingContinuations = continuations
        continuations.removeAll()
        for continuation in waitingContinuations {
            continuation.resume()
        }
    }

    func waitForFinish() async {
        if didFinish { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

@MainActor
@Test func syncFetchesParsesAndPersistsCurrentBlock() async throws {
    let container = try ModelContainer(for: Block.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8",
        ],
        rows: 20,
        cols: 60
    )
    let client = StubClient(titles: ["Intro", "Block 27"], grid: grid)
    let sync = SyncCoordinator(client: client, context: container.mainContext)

    await sync.sync(spreadsheetId: "sid")

    #expect(sync.state == .idle)
    let blocks = try container.mainContext.fetch(FetchDescriptor<Block>())
    #expect(blocks.count == 1)
    #expect(blocks[0].tabName == "Block 27")
}

@MainActor
@Test func syncIngestsLastPerformedEntriesFromParsedBlock() async throws {
    let container = try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "sync-last-performed-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
    let expectedDate = try #require(DateFormatter.testDate.date(from: "5/1/2026"))
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "C13": "5/1/2026",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "2", "F15": "5", "H15": "RPE8",
            "K15": "185x5@8",
            "K16": "195x5@9",
        ],
        rows: 20,
        cols: 60
    )
    let client = StubClient(titles: ["Intro", "Block 27"], grid: grid)
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    let sync = SyncCoordinator(
        client: client,
        context: container.mainContext,
        lastPerformedLookupRefresher: lookupStore
    )

    await sync.sync(spreadsheetId: "sid")

    let entries = try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>())
    let entry = try #require(entries.first)
    #expect(entries.count == 1)
    #expect(entry.fullName == "Squat")
    #expect(entry.result == SetLog(weight: .pounds(195), reps: 5, rpe: 9))
    #expect(entry.performedOn == expectedDate)
    #expect(entry.source == "Block 27 · W1 D1")
    let lookupEntry = try #require(
        lookupStore.snapshot.lookup(exerciseName: "Squat", baseName: "Squat")
    )
    #expect(lookupEntry.resultText == "195x5@9")
    #expect(lookupEntry.sourceText == "Block 27 · W1 D1")
}

@MainActor
@Test func syncGoesOfflineOnNetworkError() async throws {
    let container = try ModelContainer(for: Block.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let client = StubClient(titles: [], grid: [], failOffline: true)
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    await sync.sync(spreadsheetId: "sid")
    #expect(sync.state == .offline)
}

@MainActor
@Test func syncBackfillsMissingLastPerformedEntriesFromHistoricalBlocksAndStopsWhenCovered() async throws {
    let container = try makeSyncContainer()
    let backfillCompletion = BackfillCompletionProbe()
    let client = BackfillStubClient(
        titles: ["Intro", "Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": currentGridWithPendingSquat(),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026"),
        ]
    )
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    let sync = SyncCoordinator(
        client: client,
        context: container.mainContext,
        lastPerformedLookupRefresher: lookupStore,
        lastPerformedBackfillObserver: backfillCompletion
    )

    await sync.sync(spreadsheetId: "sid")
    await backfillCompletion.waitForFinish()

    let entry = try #require(
        LastPerformedIndex(context: container.mainContext)
            .lookup(exerciseName: "Squat", baseName: "Squat")
    )
    #expect(entry.result == SetLog(weight: .pounds(245), reps: 5, rpe: 8))
    #expect(entry.source == "Block 26 · W1 D1")
    #expect(await client.recorder.tabs() == ["Block 27", "Block 26"])
    let lookupEntry = try #require(
        lookupStore.snapshot.lookup(exerciseName: "Squat", baseName: "Squat")
    )
    #expect(lookupEntry.resultText == "245x5@8")
    #expect(lookupEntry.sourceText == "Block 26 · W1 D1")
}

@MainActor
@Test func syncSkipsHistoricalBackfillWhenCurrentBlockAlreadyCoversExercises() async throws {
    let container = try makeSyncContainer()
    let backfillCompletion = BackfillCompletionProbe()
    let client = BackfillStubClient(
        titles: ["Intro", "Block 26", "Block 27"],
        grids: [
            "Block 27": historicalGrid(exerciseName: "Squat", log: "255x5@8", date: "5/1/2026"),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
        ]
    )
    let sync = SyncCoordinator(
        client: client,
        context: container.mainContext,
        lastPerformedBackfillObserver: backfillCompletion
    )

    await sync.sync(spreadsheetId: "sid")
    await backfillCompletion.waitForFinish()

    #expect(sync.state == .idle)
    #expect(await client.recorder.tabs() == ["Block 27"])
}

@MainActor
@Test func syncLaunchesHistoricalBackfillWithoutWaitingForIt() async throws {
    let container = try makeSyncContainer()
    let backfillCompletion = BackfillCompletionProbe()
    let recorder = FetchRecorder()
    let client = BackfillStubClient(
        titles: ["Block 26", "Block 27"],
        grids: [
            "Block 27": currentGridWithPendingSquat(),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
        ],
        suspendedTabs: ["Block 26"],
        recorder: recorder
    )
    let sync = SyncCoordinator(
        client: client,
        context: container.mainContext,
        lastPerformedBackfillObserver: backfillCompletion
    )

    let syncTask = Task {
        await sync.sync(spreadsheetId: "sid")
        await recorder.markSyncReturned()
    }
    _ = try #require(await waitForFetchedTab("Block 26", recorder: recorder))

    #expect(await recorder.didSyncReturn())
    #expect(sync.state == .idle)

    await recorder.release()
    await syncTask.value
    await backfillCompletion.waitForFinish()
    _ = try #require(
        LastPerformedIndex(context: container.mainContext)
            .lookup(exerciseName: "Squat", baseName: "Squat")
    )
}

@MainActor
@Test func syncIgnoresHistoricalBackfillNetworkErrorsAndContinuesScanning() async throws {
    let container = try makeSyncContainer()
    let backfillCompletion = BackfillCompletionProbe()
    let client = BackfillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": currentGridWithPendingSquat(),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026"),
        ],
        failingTabs: ["Block 26"]
    )
    let sync = SyncCoordinator(
        client: client,
        context: container.mainContext,
        lastPerformedBackfillObserver: backfillCompletion
    )

    await sync.sync(spreadsheetId: "sid")
    await backfillCompletion.waitForFinish()

    let entry = try #require(
        LastPerformedIndex(context: container.mainContext)
            .lookup(exerciseName: "Squat", baseName: "Squat")
    )

    #expect(sync.state == .idle)
    #expect(entry.source == "Block 25 · W1 D1")
    #expect(await client.recorder.tabs() == ["Block 27", "Block 26", "Block 25"])
}

extension DateFormatter {
    fileprivate static let testDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

@MainActor
private func makeSyncContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "sync-backfill-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

private func currentGridWithPendingSquat() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "C13": "5/1/2026",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8",
        ],
        rows: 20,
        cols: 60
    )
}

private func historicalGrid(exerciseName: String, log: String, date: String) -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "C13": date,
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Last set RPE", "K14": "Notes",
            "C15": exerciseName, "D15": "1", "F15": "5", "H15": "RPE8",
            "K15": log,
        ],
        rows: 20,
        cols: 60
    )
}

private func waitForFetchedTab(_ tab: String, recorder: FetchRecorder) async throws -> Bool {
    for _ in 0..<100 {
        if await recorder.tabs().contains(tab) {
            return true
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
}
