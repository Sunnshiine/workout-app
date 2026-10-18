import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

/// Serves one grid for every tab, and fails every write when `failUpdates` is set.
private struct RetractionStubClient: SheetsClient {
    var grid: SheetGrid
    var failUpdates = false

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 26", "Block 27"] }
    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: grid)
    }
    func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {
        if failUpdates { throw URLError(.timedOut) }
    }
}

/// A Set Log cleared in the Sheet takes its Exercise History entry with it on the next sync (#812).
@MainActor
@Test func syncRetractsTheEntryOfAnExerciseWhoseSetLogsWereClearedInTheSheet() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([
        squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1"),
        squatEntry(resultText: "305x5@8", source: "Block 26 · W4 D3")
    ])
    let sync = SyncCoordinator(
        client: RetractionStubClient(grid: squatGrid()),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    let entries = try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.map(\.source) == ["Block 26 · W4 D3"])
    #expect(lookupStore.snapshot.lookup(for: "Squat")?.sourceText == "Block 26 · W4 D3")
}

/// A Set Log still in the queue has not reached the Sheet yet, so the Sheet's empty cell is no
/// evidence that the athlete took it back.
@MainActor
@Test func syncKeepsTheEntryOfASetLogStillQueuedForTheSheet() async throws {
    let container = try makeRetractionContainer()
    let context = container.mainContext
    let lookupStore = LastPerformedLookupStore(context: context)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1")])
    context.insert(
        PendingWrite(
            session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
            dayNumbering: .headerNumber,
            exerciseName: "Squat",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "315x5@7",
            expectedCurrentValue: ""
        )
    )
    try context.save()
    let sync = SyncCoordinator(
        client: RetractionStubClient(grid: squatGrid(), failUpdates: true),
        context: context,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    #expect(try context.fetchCount(FetchDescriptor<PendingWrite>()) == 1)
    let entries = try context.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.map(\.resultText) == ["315x5@7"])
}

/// A skip is no Set Log, so a Session whose only Set the Sheet now reads as Skipped gives up its entry.
@MainActor
@Test func syncRetractsTheEntryOfAnExerciseTheSheetNowReadsAsSkipped() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1")])
    let sync = SyncCoordinator(
        client: RetractionStubClient(grid: squatGrid(notes: "skip")),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    #expect(try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>()).isEmpty)
}

/// With its Notes header renamed, a Session's Set Logs go unread rather than missing, so the entry stays.
@MainActor
@Test func syncKeepsTheEntryOfASessionWhoseNotesColumnItCannotFind() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1")])
    let sync = SyncCoordinator(
        client: RetractionStubClient(grid: squatGrid(notesHeader: "Log", notes: "315x5@7")),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    let entries = try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.map(\.resultText) == ["315x5@7"])
}

/// A write the Sheet refused still shows its Set as Logged, so its entry stays with it.
@MainActor
@Test func syncKeepsTheEntryOfASetLogTheSheetRefusedButTheAppStillShows() async throws {
    let container = try makeRetractionContainer()
    let context = container.mainContext
    let lookupStore = LastPerformedLookupStore(context: context)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1")])
    let write = PendingWrite(
        session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
        dayNumbering: .headerNumber,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "315x5@7",
        expectedCurrentValue: ""
    )
    context.insert(write)
    write.status = .conflict
    try context.save()
    let sync = SyncCoordinator(
        client: RetractionStubClient(grid: squatGrid()),
        context: context,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    let block = try #require(try context.fetch(FetchDescriptor<Block>()).first)
    #expect(block.setsByID.values.map(\.state) == [.logged])
    let entries = try context.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.map(\.resultText) == ["315x5@7"])
}

@MainActor
private func makeRetractionContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        LastPerformedEntry.self,
        HistoryFillCursor.self,
        configurations: ModelConfiguration(
            "sync-entry-retraction-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

private func squatEntry(resultText: String, source: String) -> LastPerformedEntry {
    LastPerformedEntry(
        exerciseName: "Squat",
        resultText: resultText,
        performedOn: .distantPast,
        source: source
    )
}

/// Block 27 W1 D1 with one Squat Set. By default the Notes column holds no Set Log.
private func squatGrid(notesHeader: String = "Notes", notes: String = "") -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": notesHeader,
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE7", "K15": notes
        ],
        rows: 24,
        cols: 30
    )
}
