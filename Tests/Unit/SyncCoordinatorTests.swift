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
    #expect(sync.state == .idle)
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
@Test func historyFillIndexRefusalReachesSyncStateAsAConflict() async throws {
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
    #expect(sync.state == .conflict(["Exercise History fill failed: the index is full"]))
}

/// Every other halt stays out of the athlete's way: the fill stops, and sync's own state is
/// whatever the sync itself reported (#514 owns where background-index errors go).
@MainActor
@Test func historyFillHaltOnAnUnreadableTabLeavesSyncStateAlone() async throws {
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
    #expect(sync.state == .idle)
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
