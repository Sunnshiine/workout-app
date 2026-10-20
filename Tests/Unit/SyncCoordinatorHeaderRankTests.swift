import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

final class HeaderRankStubClient: SheetsClient, @unchecked Sendable {
    var grid: SheetGrid
    var writes: [SheetCellWrite] = []
    var offlineFetches = 0
    var failingUpdates = 0
    var offlineFromFetch = Int.max
    private var fetches = 0

    init(grid: SheetGrid) {
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        if offlineFetches > 0 {
            offlineFetches -= 1
            throw URLError(.notConnectedToInternet)
        }
        fetches += 1
        if fetches >= offlineFromFetch {
            throw URLError(.notConnectedToInternet)
        }
        return SheetSnapshot(values: grid)
    }

    func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {
        if failingUpdates > 0 {
            failingUpdates -= 1
            throw URLError(.notConnectedToInternet)
        }
        writes.append(contentsOf: cells)
    }
}

@MainActor
func makeHeaderRankContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

func headerRankPendingWrite(
    createdAt: TimeInterval,
    day: Int = 1,
    dayNumbering: DayNumbering,
    setIndex: Int = 0,
    column: PendingWriteColumn = .notes,
    valueToWrite: String
) -> PendingWrite {
    PendingWrite(
        createdAt: Date(timeIntervalSince1970: createdAt),
        session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: day)),
        dayNumbering: dayNumbering,
        exerciseName: "Squat",
        setIndex: setIndex,
        column: column,
        operation: .upsert,
        valueToWrite: valueToWrite,
        expectedCurrentValue: ""
    )
}

let dayHeadersChangedMeaning = "The sheet's Day headers changed meaning since this Set was logged. Log it again."

func threeSquatDayGroups(headedBy headers: [String?], notes: [String: String] = [:]) -> SheetGrid {
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

private func oneSetSquatDayGroupsWithLastSetRPE(headedBy headers: [String]) -> SheetGrid {
    var cells: [String: String] = [:]
    for ((name, sets, rpe, notesColumn), header) in zip([("C", "D", "I", "K"), ("S", "T", "Y", "AA")], headers) {
        cells["\(name)12"] = header
        cells["\(sets)14"] = "Sets"
        cells["\(rpe)14"] = "Last set RPE"
        cells["\(notesColumn)14"] = "Notes"
        cells["\(name)15"] = "Squat"
        cells["\(sets)15"] = "1"
    }
    return gridFromA1(cells, rows: 24, cols: 40)
}

@MainActor
private func loggedSquatSets(in ctx: ModelContext) throws -> [String] {
    let week = try ctx.fetch(FetchDescriptor<Block>()).first?.weeks.first { $0.number == 1 }
    var logged: [String] = []
    for session in (week?.sessions ?? []).sorted(by: { $0.dayNumber < $1.dayNumber }) {
        let sets: [ExerciseSet] = session.exercises.filter { $0.exerciseName == "Squat" }.flatMap(\.sets)
        for set in sets.sorted(by: { $0.index < $1.index }) where set.state == .logged {
            logged.append("w1d\(session.dayNumber) s\(set.index)=\(set.setLog?.formatted ?? "")")
        }
    }
    return logged
}

@MainActor
@Test func aRefusedHeaderRankWriteShowsOnNeitherSessionWhileTheHeadersStaySwapped() async throws {
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    ctx.insert(headerRankPendingWrite(createdAt: 1, dayNumbering: .legacyHeaderRank, setIndex: 1, valueToWrite: "190x5@8"))
    try ctx.save()
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: ["Day 2", "Day 1"], notes: ["K15": "185x5@8"]))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.sync(spreadsheetId: "sid")

    #expect(sync.outcome == .writesRefused(["Squat: \(dayHeadersChangedMeaning)"]))
    let loggedAfterTheRefusingSync = try loggedSquatSets(in: ctx)
    #expect(loggedAfterTheRefusingSync == ["w1d2 s0=185x5@8"])

    await sync.sync(spreadsheetId: "sid")

    #expect(sync.outcome == .clear)
    #expect(client.writes.isEmpty)
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.map(\.status) == [.conflict])
    #expect(writes.map(\.lastError) == [dayHeadersChangedMeaning])
    let loggedAfterALaterSync = try loggedSquatSets(in: ctx)
    #expect(loggedAfterALaterSync == ["w1d2 s0=185x5@8"])
}

@MainActor
@Test func aFlushThatRefusesAWriteAndThenStopsForRetryReportsTheRefusal() async throws {
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    ctx.insert(headerRankPendingWrite(createdAt: 1, dayNumbering: .legacyHeaderRank, valueToWrite: "190x5@8"))
    ctx.insert(headerRankPendingWrite(createdAt: 2, dayNumbering: .headerNumber, setIndex: 1, valueToWrite: "195x5@8"))
    try ctx.save()
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: ["Day 2", "Day 1"]))
    client.failingUpdates = 1
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(sync.outcome == .writesRefused(["Squat: \(dayHeadersChangedMeaning)"]))
    #expect(client.writes.isEmpty)
    let afterTheStoppedFlush = try ctx.fetch(FetchDescriptor<PendingWrite>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(afterTheStoppedFlush.map(\.status) == [.conflict, .pending])

    await sync.flushPending(spreadsheetId: "sid")

    #expect(sync.outcome == .clear)
    #expect(client.writes.map(\.target) == [SheetWriteTarget(tabName: "Block 27", a1: "AA15")])
    let afterTheRetry = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(afterTheRetry.map(\.status) == [.conflict])
}

@MainActor
@Test func aFlushThatStopsForRetryAfterAnEarlierRefusalCountsOnlyTheWritesStillQueued() async throws {
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    ctx.insert(headerRankPendingWrite(createdAt: 1, dayNumbering: .legacyHeaderRank, valueToWrite: "190x5@8"))
    ctx.insert(headerRankPendingWrite(createdAt: 2, dayNumbering: .headerNumber, setIndex: 1, valueToWrite: "195x5@8"))
    try ctx.save()
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: ["Day 2", "Day 1"]))
    client.failingUpdates = 2
    let sync = SyncCoordinator(client: client, context: ctx)
    await sync.flushPending(spreadsheetId: "sid")
    #expect(sync.outcome == .writesRefused(["Squat: \(dayHeadersChangedMeaning)"]))

    await sync.flushPending(spreadsheetId: "sid")

    #expect(sync.outcome == .writesQueued(1))
    #expect(client.writes.isEmpty)
    let records = try ctx.fetch(FetchDescriptor<PendingWrite>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(records.map(\.status) == [.conflict, .pending])
}

@MainActor
private func queueLandingRefusedAndOverlappingWrites(
    overlapping overlap: PendingWrite,
    in ctx: ModelContext
) throws {
    ctx.insert(headerRankPendingWrite(createdAt: 1, dayNumbering: .headerNumber, valueToWrite: "190x5@8"))
    ctx.insert(headerRankPendingWrite(createdAt: 2, dayNumbering: .legacyHeaderRank, valueToWrite: "185x5@8"))
    ctx.insert(overlap)
    try ctx.save()
}

@MainActor
@Test func aFlushWhoseBatchFailsMidLoopAfterAnEarlierRefusalReportsTheRefusal() async throws {
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    try queueLandingRefusedAndOverlappingWrites(
        overlapping: headerRankPendingWrite(createdAt: 3, dayNumbering: .headerNumber, setIndex: 1, valueToWrite: "195x5@8"),
        in: ctx
    )
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: ["Day 2", "Day 1"]))
    client.failingUpdates = 1
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(sync.outcome == .writesRefused(["Squat: \(dayHeadersChangedMeaning)"]))
    #expect(client.writes.isEmpty)
    let records = try ctx.fetch(FetchDescriptor<PendingWrite>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(records.map(\.status) == [.pending, .conflict, .pending])
}

@MainActor
@Test func aFlushWhoseRefetchFailsAfterAnEarlierRefusalReportsTheRefusal() async throws {
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    let relog = headerRankPendingWrite(createdAt: 3, dayNumbering: .headerNumber, valueToWrite: "195x5@8")
    try queueLandingRefusedAndOverlappingWrites(overlapping: relog, in: ctx)
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: ["Day 2", "Day 1"]))
    client.offlineFromFetch = 2
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(sync.outcome == .writesRefused(["Squat: \(dayHeadersChangedMeaning)"]))
    #expect(client.writes == [SheetCellWrite(tabName: "Block 27", a1: "AA15", value: "190x5@8")])
    #expect(relog.status == .pending)
    #expect(relog.retryCount == 1)
}

@MainActor
@Test func aRefusedHeaderRankWriteStaysUnloggedOnceTheCoachRestoresTheHeadersSoItsRelogLands() async throws {
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    ctx.insert(headerRankPendingWrite(createdAt: 1, dayNumbering: .legacyHeaderRank, valueToWrite: "190x5@8"))
    try ctx.save()
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: ["Day 2", "Day 1"]))
    let sync = SyncCoordinator(client: client, context: ctx)
    await sync.sync(spreadsheetId: "sid")
    #expect(sync.outcome == .writesRefused(["Squat: \(dayHeadersChangedMeaning)"]))
    client.grid = threeSquatDayGroups(headedBy: ["Day 1", "Day 2"])

    await sync.sync(spreadsheetId: "sid")

    #expect(sync.outcome == .clear)
    let loggedOnceTheHeadersAreRestored = try loggedSquatSets(in: ctx)
    #expect(loggedOnceTheHeadersAreRestored == [])
    let refused = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(refused.map(\.status) == [.conflict])
    #expect(refused.map(\.lastError) == [dayHeadersChangedMeaning])

    let store = WorkoutStore(context: ctx, defaults: .inMemory())
    store.reload()
    let set = try #require(
        store.block?.weeks.first?.sessions.first { $0.dayNumber == 1 }?.exercises.first?.sets.first { $0.index == 0 }
    )
    try store.log(set, as: SetLog(weight: .pounds(195), reps: 5, rpe: .eight))
    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.writes == [SheetCellWrite(tabName: "Block 27", a1: "K15", value: "195x5@8")])
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
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    let write = headerRankPendingWrite(createdAt: 1, dayNumbering: .legacyHeaderRank, valueToWrite: "190x5@8")
    ctx.insert(write)
    try ctx.save()
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: headers))
    client.offlineFetches = 1
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.sync(spreadsheetId: "sid")

    #expect(sync.outcome == .clear)
    #expect(client.writes.isEmpty)
    #expect(write.status == .pending)
    #expect(write.retryCount == 1)
    let overlaid = try loggedSquatSets(in: ctx)
    #expect(overlaid == logged)
}

@MainActor
@Test func aRefusedHeaderRankSetLogLeavesAHeaderNumberLastSetRPEForTheSameCoordinatesToLand() async throws {
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    ctx.insert(headerRankPendingWrite(createdAt: 1, dayNumbering: .legacyHeaderRank, valueToWrite: "185x5@8"))
    ctx.insert(headerRankPendingWrite(createdAt: 2, dayNumbering: .headerNumber, valueToWrite: "190x5@9"))
    ctx.insert(headerRankPendingWrite(createdAt: 3, dayNumbering: .headerNumber, column: .lastSetRPE, valueToWrite: "9"))
    try ctx.save()
    let client = HeaderRankStubClient(grid: oneSetSquatDayGroupsWithLastSetRPE(headedBy: ["Day 2", "Day 1"]))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(
        client.writes == [
            SheetCellWrite(tabName: "Block 27", a1: "AA15", value: "190x5@9"),
            SheetCellWrite(tabName: "Block 27", a1: "Y15", value: "9")
        ]
    )
    #expect(sync.outcome == .writesRefused(["Squat: \(dayHeadersChangedMeaning)"]))
    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(remaining.map(\.valueToWrite) == ["185x5@8"])
    #expect(remaining.map(\.status) == [.conflict])
}

@MainActor
@Test func aSetLoggedOnABlockCachedBeforeHeaderNumberingIsRefusedOnceTheHeadersReadSwapped() async throws {
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: ["Day 1", "Day 2"]))
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
    client.grid = threeSquatDayGroups(headedBy: ["Day 2", "Day 1"])

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.writes.isEmpty)
    #expect(sync.outcome == .writesRefused(["Squat: \(dayHeadersChangedMeaning)"]))
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.map(\.status) == [.conflict])
    #expect(writes.map(\.lastError) == [dayHeadersChangedMeaning])
}

@MainActor
@Test func aSetLoggedOnABlockThisBuildParsedFromSwappedHeadersLandsUnderItsDayHeader() async throws {
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: ["Day 2", "Day 1"]))
    let sync = SyncCoordinator(client: client, context: ctx)
    await sync.sync(spreadsheetId: "sid")
    let store = WorkoutStore(context: ctx, defaults: .inMemory())
    store.reload()
    let set = try #require(
        store.block?.weeks.first?.sessions.first { $0.dayNumber == 1 }?.exercises.first?.sets.first { $0.index == 0 }
    )
    try store.log(set, as: SetLog(weight: .pounds(190), reps: 5, rpe: .eight))

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.writes == [SheetCellWrite(tabName: "Block 27", a1: "AA15", value: "190x5@8")])
    #expect(sync.outcome == .clear)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
}
