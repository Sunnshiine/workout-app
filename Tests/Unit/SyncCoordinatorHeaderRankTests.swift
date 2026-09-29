import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private final class HeaderRankStubClient: SheetsClient, @unchecked Sendable {
    var grid: SheetGrid
    var updates: [(String, [[String]])] = []
    var offlineFetches = 0

    init(grid: SheetGrid) {
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        if offlineFetches > 0 {
            offlineFetches -= 1
            throw URLError(.notConnectedToInternet)
        }
        return SheetSnapshot(values: grid)
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        updates.append((range, values))
    }

    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
        self.updates.append(contentsOf: updates.map { ($0.range, $0.values) })
    }
}

@MainActor
private func makeHeaderRankContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func headerRankPendingWrite(
    createdAt: TimeInterval,
    day: Int = 1,
    dayNumbering: DayNumbering,
    setIndex: Int = 0,
    column: PendingWriteColumn = .notes,
    valueToWrite: String
) -> PendingWrite {
    PendingWrite(
        createdAt: Date(timeIntervalSince1970: createdAt),
        blockTab: "Block 27",
        week: 1,
        day: day,
        dayNumbering: dayNumbering,
        exerciseName: "Squat",
        setIndex: setIndex,
        column: column,
        operation: .upsert,
        valueToWrite: valueToWrite,
        expectedCurrentValue: ""
    )
}

private let dayHeadersChangedMeaning = "The sheet's Day headers changed meaning since this Set was logged. Log it again."

private func threeSquatDayGroups(headedBy headers: [String?], notes: [String: String] = [:]) -> SheetGrid {
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
            + "and on this sheet rank 1 and the header Day 1 do not name the same Session."
    ),
    HeaderRankRefusal(
        testDescription: "U2q swapped",
        headers: ["Day 2", "Day 1"],
        notes: [:],
        day: 1,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 1 was queued by header rank, "
            + "and on this sheet rank 1 and the header Day 1 do not name the same Session."
    ),
    HeaderRankRefusal(
        testDescription: "U3 Day 1 cleared, AQ15 logged",
        headers: [nil, "Day 2", "Day 3"],
        notes: ["AQ15": "185x5@8"],
        day: 2,
        setIndex: 1,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and on this sheet rank 2 and the header Day 2 do not name the same Session."
    ),
    HeaderRankRefusal(
        testDescription: "U3q Day 1 cleared",
        headers: [nil, "Day 2", "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and on this sheet rank 2 and the header Day 2 do not name the same Session."
    ),
    HeaderRankRefusal(
        testDescription: "U3r Day 1 cleared, rank 1",
        headers: [nil, "Day 2", "Day 3"],
        notes: [:],
        day: 1,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 1 was queued by header rank, "
            + "and on this sheet rank 1 and the header Day 1 do not name the same Session."
    ),
    HeaderRankRefusal(
        testDescription: "U4 middle cleared",
        headers: ["Day 1", nil, "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and on this sheet rank 2 and the header Day 2 do not name the same Session."
    ),
    HeaderRankRefusal(
        testDescription: "U5 gap",
        headers: ["Day 1", "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and on this sheet rank 2 and the header Day 2 do not name the same Session."
    ),
    HeaderRankRefusal(
        testDescription: "Day 8 at rank 3",
        headers: ["Day 1", "Day 2", "Day 8"],
        notes: [:],
        day: 3,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 3 was queued by header rank, "
            + "and on this sheet rank 3 and the header Day 3 do not name the same Session."
    ),
    HeaderRankRefusal(
        testDescription: "rank 3 past the last header, which reads Day 3",
        headers: ["Day 1", "Day 3"],
        notes: [:],
        day: 3,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 3 was queued by header rank, "
            + "and on this sheet rank 3 and the header Day 3 do not name the same Session."
    ),
    HeaderRankRefusal(
        testDescription: "Day 1 repeated, rank 1",
        headers: ["Day 1", "Day 1", "Day 3"],
        notes: [:],
        day: 1,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 1 was queued by header rank, "
            + "and on this sheet rank 1 and the header Day 1 do not name the same Session."
    ),
    HeaderRankRefusal(
        testDescription: "Day 1 repeated, rank 2",
        headers: ["Day 1", "Day 1", "Day 3"],
        notes: [:],
        day: 2,
        setIndex: 0,
        lastError: dayHeadersChangedMeaning,
        rowScan: "No row selected: Week 1, Day 2 was queued by header rank, "
            + "and on this sheet rank 2 and the header Day 2 do not name the same Session."
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
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    ctx.insert(
        headerRankPendingWrite(
            createdAt: 1,
            day: refusal.day,
            dayNumbering: .legacyHeaderRank,
            setIndex: refusal.setIndex,
            valueToWrite: "190x5@8"
        )
    )
    try ctx.save()
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: refusal.headers, notes: refusal.notes))
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
        dayNumbering: .legacyHeaderRank,
        setIndex: 1,
        range: "'Block 27'!AA15",
        value: "185x5@8, 190x5@8"
    ),
    QueuedWriteLanding(
        testDescription: "U6 Day 1 repeated, rank 3",
        headers: ["Day 1", "Day 1", "Day 3"],
        notes: [:],
        day: 3,
        dayNumbering: .legacyHeaderRank,
        setIndex: 0,
        range: "'Block 27'!AQ15",
        value: "190x5@8"
    ),
    QueuedWriteLanding(
        testDescription: "Day 8 at rank 3, rank 2",
        headers: ["Day 1", "Day 2", "Day 8"],
        notes: [:],
        day: 2,
        dayNumbering: .legacyHeaderRank,
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
    let container = try makeHeaderRankContainer()
    let ctx = container.mainContext
    ctx.insert(
        headerRankPendingWrite(
            createdAt: 1,
            day: landing.day,
            dayNumbering: landing.dayNumbering,
            setIndex: landing.setIndex,
            valueToWrite: "190x5@8"
        )
    )
    try ctx.save()
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: landing.headers, notes: landing.notes))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updates.map(\.0) == [landing.range])
    #expect(client.updates.map(\.1) == [[[landing.value]]])
    #expect(sync.outcome == .clear)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
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
    #expect(client.updates.isEmpty)
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.map(\.status) == [.conflict])
    #expect(writes.map(\.lastError) == [dayHeadersChangedMeaning])
    let loggedAfterALaterSync = try loggedSquatSets(in: ctx)
    #expect(loggedAfterALaterSync == ["w1d2 s0=185x5@8"])
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

    #expect(client.updates.map(\.0) == ["'Block 27'!K15"])
    #expect(client.updates.map(\.1) == [[["195x5@8"]]])
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
    #expect(client.updates.isEmpty)
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

    #expect(client.updates.map(\.0) == ["'Block 27'!AA15", "'Block 27'!Y15"])
    #expect(client.updates.map(\.1) == [[["190x5@9"]], [["9"]]])
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

    #expect(client.updates.isEmpty)
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

    #expect(client.updates.map(\.0) == ["'Block 27'!AA15"])
    #expect(client.updates.map(\.1) == [[["190x5@8"]]])
    #expect(sync.outcome == .clear)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
}

private enum SchemaBefore749: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Block.self, PendingWrite.self] }

    @Model
    final class Block {
        @Attribute(.unique) var tabName: String
        var squatTM: Double?
        var benchTM: Double?
        var deadliftTM: Double?

        init(tabName: String) {
            self.tabName = tabName
        }
    }

    @Model
    final class PendingWrite {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var blockTab: String
        var week: Int
        var day: Int
        var exerciseName: String
        var setIndex: Int
        var columnRaw: String
        var operationRaw: String
        var valueToWrite: String?
        var expectedCurrentValue: String
        var statusRaw: String
        var retryCount: Int
        var lastError: String?

        init(day: Int, setIndex: Int, valueToWrite: String) {
            id = UUID()
            createdAt = Date(timeIntervalSince1970: 1)
            blockTab = "Block 27"
            week = 1
            self.day = day
            exerciseName = "Squat"
            self.setIndex = setIndex
            columnRaw = "notes"
            operationRaw = "upsert"
            self.valueToWrite = valueToWrite
            expectedCurrentValue = ""
            statusRaw = "pending"
            retryCount = 0
            lastError = nil
        }
    }
}

@MainActor
private func storeWrittenBefore749(in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent("store.sqlite")
    let schema = Schema(versionedSchema: SchemaBefore749.self)
    let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
    container.mainContext.insert(SchemaBefore749.Block(tabName: "Block 27"))
    container.mainContext.insert(SchemaBefore749.PendingWrite(day: 1, setIndex: 0, valueToWrite: "190x5@8"))
    try container.mainContext.save()
    return url
}

@MainActor
private func openWithThisBuild(_ store: URL, client: HeaderRankStubClient) throws -> WorkoutApplication {
    try WorkoutApplication(
        environment: AppEnvironment(
            storage: .file(store),
            sheetsClient: client,
            defaults: .inMemory(),
            now: { Date(timeIntervalSince1970: 2) },
            seed: nil
        )
    )
}

private func makeMigrationDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("header-rank-migration-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@MainActor
@Test func aWriteInAStoreWrittenBefore749IsRefusedWhereTheDayHeadersReadSwapped() async throws {
    let directory = try makeMigrationDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try storeWrittenBefore749(in: directory)
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: ["Day 2", "Day 1"]))
    let app = try openWithThisBuild(store, client: client)

    await app.sync.flushPending(spreadsheetId: "sid")

    #expect(client.updates.isEmpty)
    #expect(app.sync.outcome == .writesRefused(["Squat: \(dayHeadersChangedMeaning)"]))
    let writes = try app.container.mainContext.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.map(\.status) == [.conflict])
    #expect(writes.map(\.lastError) == [dayHeadersChangedMeaning])
    let blocks = try app.container.mainContext.fetch(FetchDescriptor<Block>())
    #expect(blocks.map(\.dayNumbering) == [.legacyHeaderRank])
}

@MainActor
@Test func aWriteInAStoreWrittenBefore749LandsWhereItsRankAndNumberAgree() async throws {
    let directory = try makeMigrationDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try storeWrittenBefore749(in: directory)
    let client = HeaderRankStubClient(grid: threeSquatDayGroups(headedBy: ["Day 1", "Day 2"]))
    let app = try openWithThisBuild(store, client: client)

    await app.sync.flushPending(spreadsheetId: "sid")

    #expect(client.updates.map(\.0) == ["'Block 27'!K15"])
    #expect(client.updates.map(\.1) == [[["190x5@8"]]])
    #expect(app.sync.outcome == .clear)
    #expect(try app.container.mainContext.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    let blocks = try app.container.mainContext.fetch(FetchDescriptor<Block>())
    #expect(blocks.map(\.dayNumbering) == [.legacyHeaderRank])
}
