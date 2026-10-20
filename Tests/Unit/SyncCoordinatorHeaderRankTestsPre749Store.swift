import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

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
            dictationRecords: .inMemory,
            sheetsClient: client,
            defaults: .inMemory(),
            now: { Date(timeIntervalSince1970: 2) }
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

    #expect(client.writes.isEmpty)
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

    #expect(client.writes == [SheetCellWrite(tabName: "Block 27", a1: "K15", value: "190x5@8")])
    #expect(app.sync.outcome == .clear)
    #expect(try app.container.mainContext.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    let blocks = try app.container.mainContext.fetch(FetchDescriptor<Block>())
    #expect(blocks.map(\.dayNumbering) == [.legacyHeaderRank])
}
