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

    #expect(sync.outcome == .clear)
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
        lastPerformed: lookupStore
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
    #expect(sync.outcome == .sheetUnreachable)
    #expect(sync.isSyncing == false)
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
                setLog: SetLog(weight: .pounds(185), reps: 5, rpe: .eight)
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
@Test(.timeLimit(.minutes(1))) func syncLaunchesTheExerciseHistoryFillWithoutWaitingForIt() async throws {
    let container = try makeSyncContainer()
    let client = HistoryFillStubClient(
        titles: ["Block 26", "Block 27"],
        grids: [
            "Block 27": currentGridWithPendingSquat(),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026")
        ],
        suspendedTabs: ["Block 26"]
    )
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    let fill = ExerciseHistoryFill(client: client, context: container.mainContext, index: lookupStore)
    let sync = SyncCoordinator(
        client: client,
        context: container.mainContext,
        lastPerformed: lookupStore,
        historyFill: fill
    )

    await sync.sync(spreadsheetId: "sid")

    // Block 26's read is still parked, so sync returned while the fill was mid-flight.
    #expect(sync.outcome == .clear)
    #expect(sync.isSyncing == false)
    #expect(lookupStore.snapshot.lookup(for: "Squat") == nil)
    let inFlight = try #require(sync.inFlightHistoryFill)

    await client.recorder.release()

    #expect(await inFlight.value == .tabsExhausted(tabsIngested: 1))
    #expect(lookupStore.snapshot.lookup(for: "Squat")?.resultText == "245x5@8")
    #expect(fill.progress == nil)
}

/// A tab that reads fine but cannot be stored is reported to the coach, because the halt leaves the
/// coverage count short and the next sync will come straight back to this tab.
@MainActor
@Test func historyFillIndexRefusalReachesTheSyncOutcome() async throws {
    let container = try makeSyncContainer()
    let client = HistoryFillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": currentGridWithPendingSquat(),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
        ]
    )
    let index = RefusingIndex()
    let sync = SyncCoordinator(
        client: client,
        context: container.mainContext,
        lastPerformed: index,
        historyFill: ExerciseHistoryFill(client: client, context: container.mainContext, index: index)
    )

    await sync.sync(spreadsheetId: "sid")
    let outcome = await sync.inFlightHistoryFill?.value

    #expect(outcome == .halted(tab: "Block 26", reason: .indexRejected("the index is full"), tabsIngested: 0))
    #expect(sync.outcome == .historyFillFailed("the index is full"))
    #expect(sync.isSyncing == false)
}

@MainActor
@Test func historyFillHaltOnAnUnreadableTabLeavesTheSyncOutcomeAlone() async throws {
    let container = try makeSyncContainer()
    let client = HistoryFillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": currentGridWithPendingSquat(),
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
        ],
        unreadableTabs: ["Block 26"]
    )
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    let sync = SyncCoordinator(
        client: client,
        context: container.mainContext,
        lastPerformed: lookupStore,
        historyFill: ExerciseHistoryFill(client: client, context: container.mainContext, index: lookupStore)
    )

    await sync.sync(spreadsheetId: "sid")
    let outcome = await sync.inFlightHistoryFill?.value

    #expect(outcome == .halted(tab: "Block 26", reason: .unreadable, tabsIngested: 0))
    #expect(sync.outcome == .clear)
    #expect(sync.isSyncing == false)
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
            "sync-history-fill-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@MainActor
@Suite("SyncCoordinator.outcome latch and clear")
struct SyncOutcomeCharacterizationTests {
    @Test func aLocalWriteFailureCarriesTheErrorDescription() throws {
        let container = try makeContainer()
        let sync = SyncCoordinator(client: OutcomePinClient(grid: writableGrid()), context: container.mainContext)

        sync.reportLocalWriteFailure(LocalWriteFailure())

        #expect(sync.outcome == .localWriteFailed("the local store is full"))
        #expect(sync.isSyncing == false)
    }

    @Test func aWriteThatLosesToACoachEditIsRefusedWithTheExerciseNamePrefixed() async throws {
        let container = try makeContainer()
        try queueSquatLog(in: container.mainContext)
        let client = OutcomePinClient(grid: coachEditedGrid())
        let sync = SyncCoordinator(client: client, context: container.mainContext)

        await sync.flushPending(spreadsheetId: "sid")

        #expect(sync.outcome == .writesRefused(["Squat: Expected '', found 'coach edited'"]))
        #expect(client.updates.isEmpty)
    }

    @Test func aSpreadsheetWithNoBlockTabReportsNoBlockTab() async throws {
        let container = try makeContainer()
        let client = OutcomePinClient(titles: ["Intro", "Notes"], grid: writableGrid())
        let sync = SyncCoordinator(client: client, context: container.mainContext)

        let succeeded = await sync.sync(spreadsheetId: "sid")

        #expect(succeeded == false)
        #expect(sync.outcome == .noBlockTab)
        #expect(sync.isSyncing == false)
    }

    @Test func aTabWithNoDayHeadersReportsTheParserWarningVerbatim() async throws {
        let container = try makeContainer()
        let client = OutcomePinClient(grid: gridWithNoDayHeaders())
        let sync = SyncCoordinator(client: client, context: container.mainContext)

        let succeeded = await sync.sync(spreadsheetId: "sid")

        #expect(succeeded == true)
        #expect(sync.outcome == .parseWarnings(["Parse warning: no week sections (no 'Day N' headers) in Block 27"]))
    }

    @Test func aFlushRefusalOutranksTheParseWarningFromTheSameSync() async throws {
        let container = try makeContainer()
        try queueSquatLog(in: container.mainContext)
        let client = OutcomePinClient(grid: gridWithNoDayHeaders())
        let sync = SyncCoordinator(client: client, context: container.mainContext)

        await sync.sync(spreadsheetId: "sid")

        #expect(sync.outcome == .writesRefused(["Squat: Week 1 was not found in the sheet"]))
    }

    @Test func aMissingBlockTabReplacesTheRefusalTheFlushJustRecorded() async throws {
        let container = try makeContainer()
        try queueSquatLog(in: container.mainContext)
        let client = OutcomePinClient(titles: ["Intro", "Notes"], grid: coachEditedGrid())
        let sync = SyncCoordinator(client: client, context: container.mainContext)

        await sync.sync(spreadsheetId: "sid")

        #expect(sync.outcome == .noBlockTab)
        #expect(sync.isSyncing == false)
        let write = try #require(try sync.fetchPendingWriteRecords().first)
        #expect(write.status == .conflict)
        #expect(write.lastError == "Expected '', found 'coach edited'")
    }

    @Test func aLaterCleanSyncClearsTheRefusalWhileTheConflictedWriteStaysInTheStore() async throws {
        let container = try makeContainer()
        try queueSquatLog(in: container.mainContext)
        let client = OutcomePinClient(grid: coachEditedGrid())
        let sync = SyncCoordinator(client: client, context: container.mainContext)
        await sync.flushPending(spreadsheetId: "sid")
        #expect(sync.outcome == .writesRefused(["Squat: Expected '', found 'coach edited'"]))

        client.grid = writableGrid()
        await sync.sync(spreadsheetId: "sid")

        #expect(sync.outcome == .clear)
        let write = try #require(try sync.fetchPendingWriteRecords().first)
        #expect(write.status == .conflict)
        #expect(write.lastError == "Expected '', found 'coach edited'")
        #expect(client.updates.isEmpty)
    }

    @Test func flushingAnEmptyQueueClearsALocalWriteFailure() async throws {
        let container = try makeContainer()
        let sync = SyncCoordinator(client: OutcomePinClient(grid: writableGrid()), context: container.mainContext)
        sync.reportLocalWriteFailure(LocalWriteFailure())

        await sync.flushPending(spreadsheetId: "sid")

        #expect(sync.outcome == .clear)
    }

    @Test func discardingPendingWritesClearsAParseWarningItDidNotCause() async throws {
        let container = try makeContainer()
        let sync = SyncCoordinator(client: OutcomePinClient(grid: gridWithNoDayHeaders()), context: container.mainContext)
        await sync.sync(spreadsheetId: "sid")
        #expect(sync.outcome == .parseWarnings(["Parse warning: no week sections (no 'Day N' headers) in Block 27"]))

        try await sync.discardPendingWrites()

        #expect(sync.outcome == .clear)
        #expect(sync.isSyncing == false)
        #expect(try sync.fetchPendingWriteRecords().isEmpty)
    }

    @Test func aSyncWhoseUploadFailedEndsClearWithTheWriteStillQueued() async throws {
        let container = try makeContainer()
        try queueSquatLog(in: container.mainContext)
        let client = OutcomePinClient(grid: writableGrid())
        client.updatesFail = true
        let sync = SyncCoordinator(client: client, context: container.mainContext)

        await sync.sync(spreadsheetId: "sid")

        #expect(sync.outcome == .clear)
        #expect(SyncStatusBannerPresentation(outcome: sync.outcome, isSyncing: sync.isSyncing) == nil)
        let write = try #require(try sync.fetchPendingWriteRecords().first)
        #expect(write.status == .pending)
        #expect(write.retryCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func theFlushRefusalIsInvisibleInOutcomeForTheWholeNetworkPhaseOfASync() async throws {
        let container = try makeContainer()
        try queueSquatLog(in: container.mainContext)
        let client = HeldOutcomePinClient(heldCall: .tabTitles, grid: coachEditedGrid())
        let sync = SyncCoordinator(client: client, context: container.mainContext)
        sync.reportLocalWriteFailure(LocalWriteFailure())

        let running = Task { await sync.sync(spreadsheetId: "sid") }
        await client.waitUntilHeld()

        #expect(sync.outcome == .localWriteFailed("the local store is full"))
        #expect(sync.isSyncing == true)
        let midSyncWrite = try #require(try sync.fetchPendingWriteRecords().first)
        #expect(midSyncWrite.status == .conflict)

        client.release()

        #expect(await running.value == true)
        #expect(sync.outcome == .writesRefused(["Squat: Expected '', found 'coach edited'"]))
        #expect(sync.isSyncing == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func midFlushTheCoordinatorSaysSyncingWhileTheFlushCountRefusesToAnswer() async throws {
        let container = try makeContainer()
        try queueSquatLog(in: container.mainContext)
        let client = HeldOutcomePinClient(heldCall: .tabSnapshot, grid: coachEditedGrid())
        let sync = SyncCoordinator(client: client, context: container.mainContext)

        let running = Task { await sync.flushPending(spreadsheetId: "sid") }
        await client.waitUntilHeld()

        #expect(sync.isSyncing == true)
        #expect(sync.outcome == .clear)
        var thrown: (any Error)?
        do {
            _ = try sync.hasPendingWrites()
        } catch {
            thrown = error
        }
        #expect(String(describing: try #require(thrown)) == "PendingWriteFlushInProgress()")

        client.release()
        await running.value

        #expect(sync.outcome == .writesRefused(["Squat: Expected '', found 'coach edited'"]))
        #expect(sync.isSyncing == false)
        // A conflicted write still counts as pending here, which is what keeps a sheet switch
        // blocked until the athlete discards it.
        #expect(try sync.hasPendingWrites() == true)
    }

    @Test func aFailedSyncAfterAParseWarningReportsTheSheetUnreachableAndDropsTheWarning() async throws {
        let container = try makeContainer()
        let client = OutcomePinClient(grid: gridWithNoDayHeaders())
        let sync = SyncCoordinator(client: client, context: container.mainContext)
        await sync.sync(spreadsheetId: "sid")
        #expect(sync.outcome == .parseWarnings(["Parse warning: no week sections (no 'Day N' headers) in Block 27"]))

        client.isOffline = true
        let succeeded = await sync.sync(spreadsheetId: "sid")

        #expect(succeeded == false)
        #expect(sync.outcome == .sheetUnreachable)
    }

    @Test func aFailedSyncAfterARefusedWriteKeepsTheRecordButNotTheMessage() async throws {
        let container = try makeContainer()
        try queueSquatLog(in: container.mainContext)
        let client = OutcomePinClient(grid: coachEditedGrid())
        let sync = SyncCoordinator(client: client, context: container.mainContext)
        await sync.flushPending(spreadsheetId: "sid")
        #expect(sync.outcome == .writesRefused(["Squat: Expected '', found 'coach edited'"]))

        client.isOffline = true
        await sync.sync(spreadsheetId: "sid")

        #expect(sync.outcome == .sheetUnreachable)

        client.isOffline = false
        client.grid = writableGrid()
        await sync.sync(spreadsheetId: "sid")

        #expect(sync.outcome == .clear)
        #expect(SyncStatusBannerPresentation(outcome: sync.outcome, isSyncing: sync.isSyncing) == nil)
        let write = try #require(try sync.fetchPendingWriteRecords().first)
        #expect(write.status == .conflict)
        #expect(write.lastError == "Expected '', found 'coach edited'")
    }
}

extension SyncOutcomeCharacterizationTests {
    fileprivate func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Block.self,
            PendingWrite.self,
            WriteTargetAuditEntry.self,
            LastPerformedEntry.self,
            HistoryFillCursor.self,
            configurations: ModelConfiguration(
                "sync-outcome-pin-\(UUID().uuidString)",
                isStoredInMemoryOnly: true
            )
        )
    }

    fileprivate func queueSquatLog(in context: ModelContext) throws {
        context.insert(
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
        try context.save()
    }

    /// Squat's Set 1 Notes cell is empty, so the queued Set Log lands in it.
    fileprivate func writableGrid() -> SheetGrid {
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

    /// A coach note occupies the header row, pushing Set 1 onto a continuation row that already
    /// holds text the app did not write. The write conflicts rather than overwrite it (ADR-0003).
    fileprivate func coachEditedGrid() -> SheetGrid {
        gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1", "K15": "Coach note", "K16": "coach edited"
            ],
            rows: 24,
            cols: 30
        )
    }

    fileprivate func gridWithNoDayHeaders() -> SheetGrid {
        gridFromA1(["C15": "Squat"], rows: 24, cols: 30)
    }
}

private struct LocalWriteFailure: LocalizedError {
    var errorDescription: String? { "the local store is full" }
}

@MainActor
private final class OutcomePinClient: SheetsClient {
    var grid: SheetGrid
    var isOffline = false
    var updatesFail = false
    private(set) var updates: [String] = []
    private let titles: [String]

    init(titles: [String] = ["Intro", "Block 27"], grid: SheetGrid) {
        self.titles = titles
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        if isOffline { throw URLError(.notConnectedToInternet) }
        return titles
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        if isOffline { throw URLError(.notConnectedToInternet) }
        return SheetSnapshot(values: grid)
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        if updatesFail { throw URLError(.timedOut) }
        updates.append(range)
    }
}

/// Holds one Sheet call open so a test can read the coordinator while a sync it did not start is
/// mid-flight, after `HeldSheetsClient` in `SettingsStoreTests`. Only the first call parks: a
/// second one must run to completion and fail an expectation rather than strand the test on a
/// continuation nobody releases.
@MainActor
private final class HeldOutcomePinClient: SheetsClient {
    /// `tabSnapshot` parks the first read a flush makes; `tabTitles` parks the first read `sync`
    /// makes after the flush has already finished.
    enum SheetCall {
        case tabTitles, tabSnapshot
    }

    private let heldCall: SheetCall
    private let titles: [String]
    private let grid: SheetGrid
    private let held = HeldCall()

    init(heldCall: SheetCall, titles: [String] = ["Intro", "Block 27"], grid: SheetGrid) {
        self.heldCall = heldCall
        self.titles = titles
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        if heldCall == .tabTitles { await held.hold() }
        return titles
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        if heldCall == .tabSnapshot { await held.hold() }
        return SheetSnapshot(values: grid)
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}

    func waitUntilHeld() async {
        await held.waitUntilHeld(orRecord: "the coordinator never reached the Sheet call this client holds")
    }

    func release() {
        held.release()
    }
}
