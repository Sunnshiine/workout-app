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
    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: grid)
    }
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}

private final class BackfillStubClient: SheetsClient, @unchecked Sendable {
    let titles: [String]
    let grids: [String: SheetGrid]
    let failingTabs: Set<String>
    let transientFailureTabs: Set<String>
    let suspendedTabs: Set<String>
    let recorder: FetchRecorder

    init(
        titles: [String],
        grids: [String: SheetGrid],
        failingTabs: Set<String> = [],
        transientFailureTabs: Set<String> = [],
        suspendedTabs: Set<String> = [],
        recorder: FetchRecorder = FetchRecorder()
    ) {
        self.titles = titles
        self.grids = grids
        self.failingTabs = failingTabs
        self.transientFailureTabs = transientFailureTabs
        self.suspendedTabs = suspendedTabs
        self.recorder = recorder
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { titles }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        await recorder.record(tabName)
        if failingTabs.contains(tabName) { throw URLError(.notConnectedToInternet) }
        if transientFailureTabs.contains(tabName) { throw SheetsError.http(429) }
        if suspendedTabs.contains(tabName) {
            await recorder.waitForRelease()
        }
        return SheetSnapshot(values: grids[tabName] ?? [])
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
    private(set) var progressEvents: [LastPerformedBackfillProgress] = []

    func lastPerformedBackfillDidProgress(_ progress: LastPerformedBackfillProgress) {
        progressEvents.append(progress)
    }

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
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8"
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
        WriteTargetAuditEntry.self,
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
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "2", "F15": "5", "H15": "RPE8",
            "K15": "185x5@8, 195x5@9"
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
    #expect(entry.resultText == "185x5@8, 195x5@9")
    #expect(entry.performedOn == expectedDate)
    #expect(entry.source == "Block 27 · W1 D1")
    let lookupEntry = try #require(
        lookupStore.snapshot.lookup(for: "Squat")
    )
    #expect(lookupEntry.resultText == "185x5@8, 195x5@9")
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
@Test func syncPreservesLocalSetLoggedAtWhenReplacingParsedBlock() async throws {
    let container = try makeLoggedAtSyncContainer()
    let context = container.mainContext
    let loggedAt = Date(timeIntervalSinceReferenceDate: 1_000)
    let block = makeLoggedSquatBlock()
    let localSet = try #require(block.weeks.first?.sessions.first?.exercises.first?.sets.first)
    localSet.loggedAt = loggedAt
    context.insert(block)
    try context.save()
    let client = StubClient(titles: ["Intro", "Block 27"], grid: loggedSquatGrid())
    let sync = SyncCoordinator(client: client, context: context)

    await sync.sync(spreadsheetId: "sid")

    let syncedBlock = try #require(try context.fetch(FetchDescriptor<Block>()).first)
    let syncedSet = try #require(
        syncedBlock.weeks.first { $0.number == 1 }?
            .sessions.first { $0.dayNumber == 1 }?
            .exercises.first { $0.name == "Squat" }?
            .sets.first { $0.index == 0 }
    )
    #expect(syncedSet.loggedAt == loggedAt)
}

@MainActor
private func makeLoggedAtSyncContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(
            "sync-preserves-logged-at-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@MainActor
private func makeLoggedSquatBlock() -> Block {
    BlockBuilder.makeBlock(
        from: ParsedBlockModel(
            tabName: "Block 27",
            weeks: [
                ParsedWeek(
                    number: 1,
                    days: [
                        ParsedSession(
                            dayNumber: 1,
                            date: nil,
                            exercises: [loggedSquatExercise()]
                        )
                    ]
                )
            ]
        )
    )
}

private func loggedSquatExercise() -> ParsedExercise {
    ParsedExercise(
        name: "Squat",
        baseName: "Squat",
        cadence: nil,
        coachNote: nil,
        sets: [
            ParsedSet(
                index: 0,
                prescribedReps: "5",
                prescribedLoad: "RPE8",
                percentOneRM: nil,
                state: .logged,
                setLog: SetLog(weight: .pounds(185), reps: 5, rpe: 8)
            )
        ]
    )
}

private func loggedSquatGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8", "K15": "185x5@8"
        ],
        rows: 20,
        cols: 60
    )
}

@MainActor
@Test func syncBackfillsHistoricalBlocksAndStopsOnTabExhaustionWhenCoverageUnreached() async throws {
    let container = try makeSyncContainer()
    let backfillCompletion = BackfillCompletionProbe()
    let client = BackfillStubClient(
        titles: ["Intro", "Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": currentGridWithPendingSquat(),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
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

    // Only two historical tabs exist, so the ≥5 coverage target is never reached; the fill
    // scans every historical tab and stops on exhaustion.
    let entry = try #require(
        LastPerformedIndex(context: container.mainContext)
            .snapshot().lookup(for: "Squat")
    )
    #expect(entry.resultText == "245x5@8")
    #expect(entry.sourceText == "Block 26 · W1 D1")
    #expect(await client.recorder.tabs() == ["Block 27", "Block 26", "Block 25"])
    let lookupEntry = try #require(
        lookupStore.snapshot.lookup(for: "Squat")
    )
    #expect(lookupEntry.resultText == "245x5@8")
    #expect(lookupEntry.sourceText == "Block 26 · W1 D1")
}

@MainActor
@Test func syncBackfillsUntilFiveEntriesPerBaseNameThenStops() async throws {
    let container = try makeSyncContainer()
    let backfillCompletion = BackfillCompletionProbe()
    // Current Block 27 logs one Squat entry; each historical tab adds one more. The ≥5
    // coverage target is reached after four historical tabs (Block 26…23), so the fill
    // never fetches the fifth historical tab, Block 22.
    let client = BackfillStubClient(
        titles: ["Block 22", "Block 23", "Block 24", "Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": historicalGrid(exerciseName: "Squat", log: "255x5@8", date: "5/1/2026"),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026"),
            "Block 24": historicalGrid(exerciseName: "Squat", log: "225x5@8", date: "4/10/2026"),
            "Block 23": historicalGrid(exerciseName: "Squat", log: "215x5@8", date: "4/3/2026"),
            "Block 22": historicalGrid(exerciseName: "Squat", log: "205x5@8", date: "3/27/2026")
        ]
    )
    let sync = SyncCoordinator(
        client: client,
        context: container.mainContext,
        lastPerformedBackfillObserver: backfillCompletion
    )

    await sync.sync(spreadsheetId: "sid")
    await backfillCompletion.waitForFinish()

    #expect(LastPerformedIndex(context: container.mainContext).entryCount(baseName: "Squat") == 5)
    #expect(await client.recorder.tabs() == ["Block 27", "Block 26", "Block 25", "Block 24", "Block 23"])
}

@MainActor
@Test func syncSkipsHistoricalBackfillWhenCoverageIsAlreadySatisfied() async throws {
    let container = try makeSyncContainer()
    // Seed five Squat entries already on device — coverage holds before any historical scan.
    try LastPerformedIndex(context: container.mainContext).ingest(
        (1...5).map { week in
            LastPerformedEntry(
                fullName: "Squat",
                baseName: "Squat",
                resultText: "24\(week)x5@8",
                performedOn: Date(timeIntervalSince1970: TimeInterval(week)),
                source: "Block 2\(week) · W1 D1"
            )
        }
    )
    let backfillCompletion = BackfillCompletionProbe()
    let client = BackfillStubClient(
        titles: ["Intro", "Block 26", "Block 27"],
        grids: [
            "Block 27": historicalGrid(exerciseName: "Squat", log: "255x5@8", date: "5/1/2026"),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026")
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
@Test func repeatedSyncsDoNotDuplicateBackfilledEntries() async throws {
    let container = try makeSyncContainer()
    let client = BackfillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": currentGridWithPendingSquat(),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
        ]
    )

    for _ in 0..<2 {
        let backfillCompletion = BackfillCompletionProbe()
        let sync = SyncCoordinator(
            client: client,
            context: container.mainContext,
            lastPerformedBackfillObserver: backfillCompletion
        )
        await sync.sync(spreadsheetId: "sid")
        await backfillCompletion.waitForFinish()
    }

    // Coverage never reached (two historical tabs), so both syncs re-scan the same tabs;
    // (fullName, source) dedup keeps the entry count at exactly the two distinct Sessions.
    #expect(LastPerformedIndex(context: container.mainContext).entryCount(baseName: "Squat") == 2)
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
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026")
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
            .snapshot().lookup(for: "Squat")
    )
}

@MainActor
@Test func syncHaltsHistoricalBackfillOnAFailedTabRatherThanSkippingIt() async throws {
    let container = try makeSyncContainer()
    let backfillCompletion = BackfillCompletionProbe()
    // Block 26 fails transiently; Block 25 lies deeper. The fill must halt at Block 26 rather than
    // skip it and reach Block 25 — a silent skip would leave a hole that corrupts the coverage count.
    let client = BackfillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": currentGridWithPendingSquat(),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
        ],
        transientFailureTabs: ["Block 26"]
    )
    let sync = SyncCoordinator(
        client: client,
        context: container.mainContext,
        lastPerformedBackfillObserver: backfillCompletion,
        tabFetchBackoff: instantBackoff()
    )

    await sync.sync(spreadsheetId: "sid")
    await backfillCompletion.waitForFinish()

    // The fill halted at Block 26 and never reached Block 25.
    #expect(sync.state == .idle)
    #expect(LastPerformedIndex(context: container.mainContext).entryCount(baseName: "Squat") == 0)
    #expect(await client.recorder.tabs().contains("Block 26"))
    #expect(await !client.recorder.tabs().contains("Block 25"))
}

@MainActor
@Test func failedTabHaltHaltsAtItsCursorThenTheNextSyncResumesFromThere() async throws {
    let container = try makeSyncContainer()
    // First sync: Block 26 ingests, Block 25 fails transiently → halt. The cursor lands on Block 26.
    let firstProbe = BackfillCompletionProbe()
    let firstClient = BackfillStubClient(
        titles: ["Block 24", "Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": currentGridWithPendingSquat(),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026"),
            "Block 24": historicalGrid(exerciseName: "Squat", log: "225x5@8", date: "4/10/2026")
        ],
        transientFailureTabs: ["Block 25"]
    )
    let firstSync = SyncCoordinator(
        client: firstClient,
        context: container.mainContext,
        lastPerformedBackfillObserver: firstProbe,
        tabFetchBackoff: instantBackoff()
    )
    await firstSync.sync(spreadsheetId: "sid")
    await firstProbe.waitForFinish()

    #expect(LastPerformedIndex(context: container.mainContext).entryCount(baseName: "Squat") == 1)
    let cursor = try #require(historyFillCursor(in: container.mainContext, spreadsheetId: "sid"))
    #expect(cursor.deepestIngestedTab == "Block 26")
    #expect(await !firstClient.recorder.tabs().contains("Block 24"))

    // Second sync — a fresh SyncCoordinator on the same persisted store, standing in for an app
    // restart. Block 25 now succeeds; the fill resumes from the cursor and never re-reads Block 26.
    let secondProbe = BackfillCompletionProbe()
    let secondRecorder = FetchRecorder()
    let secondClient = BackfillStubClient(
        titles: ["Block 24", "Block 25", "Block 26", "Block 27"],
        grids: firstClient.grids,
        recorder: secondRecorder
    )
    let secondSync = SyncCoordinator(
        client: secondClient,
        context: container.mainContext,
        lastPerformedBackfillObserver: secondProbe,
        tabFetchBackoff: instantBackoff()
    )
    await secondSync.sync(spreadsheetId: "sid")
    await secondProbe.waitForFinish()

    // Block 25 and Block 24 were ingested on resume; Block 26 was not re-read; the cursor is cleared.
    #expect(LastPerformedIndex(context: container.mainContext).entryCount(baseName: "Squat") == 3)
    #expect(await secondRecorder.tabs().contains("Block 25"))
    #expect(await secondRecorder.tabs().contains("Block 24"))
    #expect(await !secondRecorder.tabs().contains("Block 26"))
    #expect(historyFillCursor(in: container.mainContext, spreadsheetId: "sid") == nil)
}

@MainActor
@Test func historicalBackfillPublishesPerTabProgressThroughTheObserverSeam() async throws {
    let container = try makeSyncContainer()
    let probe = BackfillCompletionProbe()
    let client = BackfillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": currentGridWithPendingSquat(),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
        ]
    )
    let sync = SyncCoordinator(
        client: client,
        context: container.mainContext,
        lastPerformedBackfillObserver: probe,
        tabFetchBackoff: instantBackoff()
    )

    await sync.sync(spreadsheetId: "sid")
    await probe.waitForFinish()

    #expect(probe.progressEvents.map(\.tab) == ["Block 26", "Block 25"])
    #expect(probe.progressEvents.map(\.tabsCompleted) == [1, 2])
    #expect(probe.progressEvents.allSatisfy { $0.tabsToScan == 2 })
}

@MainActor
private func historyFillCursor(in context: ModelContext, spreadsheetId: String) -> HistoryFillCursor? {
    let descriptor = FetchDescriptor<HistoryFillCursor>(
        predicate: #Predicate { $0.spreadsheetId == spreadsheetId }
    )
    return try? context.fetch(descriptor).first
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
        WriteTargetAuditEntry.self,
        LastPerformedEntry.self,
        HistoryFillCursor.self,
        configurations: ModelConfiguration(
            "sync-backfill-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

/// A backoff with no real sleeps, so tests exercise the 429 → `.failed` path instantly.
private func instantBackoff() -> SheetsBackoff {
    SheetsBackoff(schedule: [.zero], sleep: { _ in })
}

private func currentGridWithPendingSquat() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "C13": "5/1/2026",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8"
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
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": exerciseName, "D15": "1", "F15": "5", "H15": "RPE8",
            "K15": log
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
