import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

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
        #expect(client.writes.isEmpty)
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
        #expect(client.writes.isEmpty)
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
        client.writesFail = true
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
        let client = HeldOutcomePinClient(holding: .tabTitles, grid: coachEditedGrid())
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
        let client = HeldOutcomePinClient(holding: .tabSnapshot, grid: coachEditedGrid())
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

    @Test(.timeLimit(.minutes(1)))
    func aSetLogQueuedWhileAFlushIsInFlightIsCountedWhenThatFlushCompletes() async throws {
        let container = try makeContainer()
        try queueSquatLog(in: container.mainContext)
        let client = HeldOutcomePinClient(holding: .tabSnapshot, grid: writableGrid())
        let sync = SyncCoordinator(client: client, context: container.mainContext)

        let running = Task { await sync.flushPending(spreadsheetId: "sid") }
        await client.waitUntilHeld()
        try queueSquatLog(in: container.mainContext, valueToWrite: "190x5@8")
        client.release()
        await running.value

        #expect(sync.outcome == .writesQueued(1))
        let remaining = try sync.fetchPendingWriteRecords()
        #expect(remaining.map(\.valueToWrite) == ["190x5@8"])
        #expect(remaining.map(\.status) == [.pending])
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

    fileprivate func queueSquatLog(
        in context: ModelContext,
        dayNumbering: DayNumbering = .headerNumber,
        valueToWrite: String = "185x5@8"
    ) throws {
        context.insert(
            PendingWrite(
                session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
                dayNumbering: dayNumbering,
                exerciseName: "Squat",
                setIndex: 0,
                column: .notes,
                operation: .upsert,
                valueToWrite: valueToWrite,
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
    var writesFail = false
    private(set) var writes: [SheetCellWrite] = []
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

    func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {
        if writesFail { throw URLError(.timedOut) }
        writes.append(contentsOf: cells)
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

    private let heldSheetCall: SheetCall
    private let titles: [String]
    private let grid: SheetGrid
    private let held = HeldCall()

    init(holding heldSheetCall: SheetCall, titles: [String] = ["Intro", "Block 27"], grid: SheetGrid) {
        self.heldSheetCall = heldSheetCall
        self.titles = titles
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        if heldSheetCall == .tabTitles { await held.hold() }
        return titles
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        if heldSheetCall == .tabSnapshot { await held.hold() }
        return SheetSnapshot(values: grid)
    }

    func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {}

    func waitUntilHeld() async {
        await held.waitUntilHeld(orRecord: "the coordinator never reached the Sheet call this client holds")
    }

    func release() {
        held.release()
    }
}
