import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

/// Serves one grid for every tab, and fails every write when `failUpdates` is set.
private struct RetractionStubClient: SheetsClient {
    var grid: SheetGrid
    var hiddenRows: [Int: SheetRowVisibility] = [:]
    var failUpdates = false

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 26", "Block 27"] }
    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: grid, rowVisibility: hiddenRows)
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

/// A skip is no Set Log, so a Session whose only Set the Sheet now reads as Skipped gives up its
/// entry, and the `skip` the entry itself carries is not a result the cell can hold.
@MainActor
@Test func syncRetractsTheEntryOfAnExerciseTheSheetNowReadsAsSkipped() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7, skip", source: "Block 27 · W1 D1")])
    let sync = SyncCoordinator(
        client: RetractionStubClient(grid: squatGrid(notes: "skip")),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    #expect(try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>()).isEmpty)
}

/// With its Notes header renamed, a Session's Set Logs go unread. They are still in the Sheet, so
/// the entry stays.
@MainActor
@Test func syncKeepsTheEntryOfASessionWhoseNotesHeaderWasRenamed() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1")])
    let sync = SyncCoordinator(
        client: RetractionStubClient(grid: squatGrid(notesHeader: "Athlete log", notes: "315x5@7")),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    let entries = try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.map(\.resultText) == ["315x5@7"])
}

/// A filter that hides the row below a Coach Note hides the Set Logs the parse would place there.
/// They are still in the Sheet, so the entry stays.
@MainActor
@Test func syncKeepsTheEntryOfASetLogOnARowAFilterHides() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1")])
    let sync = SyncCoordinator(
        client: RetractionStubClient(
            grid: squatGrid(notes: "Pause 2s at the bottom", extraCells: ["K16": "315x5@7, 315x5@8"]),
            hiddenRows: [15: SheetRowVisibility(hiddenByFilter: true)]
        ),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    let entries = try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.map(\.resultText) == ["315x5@7"])
}

/// A week's last Day takes its first Day's width. A wider last Day leaves its Notes column outside
/// that span, so the layout reads the Session with no Notes column. Its Set Logs went unread, not
/// missing, so the entry stays.
@MainActor
@Test func syncKeepsTheEntryOfASessionTheLayoutReadsWithNoNotesColumn() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([
        LastPerformedEntry(
            exerciseName: "Bench Press",
            resultText: "315x5@7",
            performedOn: .distantPast,
            source: "Block 27 · W1 D2"
        )
    ])
    let grid = gridFromA1(
        [
            "C12": "Day 1", "L12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "M14": "Sets", "O14": "Reps", "Q14": "Load", "T14": "Tempo", "U14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE7",
            "L15": "Bench Press", "M15": "1", "O15": "5", "Q15": "RPE7", "U15": "315x5@7"
        ],
        rows: 24,
        cols: 30
    )
    let sync = SyncCoordinator(
        client: RetractionStubClient(grid: grid),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    let entries = try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.map { "\($0.fullName)|\($0.resultText)|\($0.source)" } == ["Bench Press|315x5@7|Block 27 · W1 D2"])
}

/// A second "Notes" header in the Session makes the layout pick the column with the Coach Note, so
/// the Set Log in the other goes unread. It is still in the Sheet, so the entry stays.
@MainActor
@Test func syncKeepsTheEntryOfASetLogBehindADuplicateNotesHeader() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1")])
    let sync = SyncCoordinator(
        client: RetractionStubClient(
            grid: squatGrid(notes: "315x5@7", extraCells: ["J14": "Notes", "J15": "Brace hard"])
        ),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    let entries = try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.map(\.resultText) == ["315x5@7"])
}

/// A remark, a unit, or a capital X makes the header cell read as a Coach Note, so the parse
/// places no Set Log. The numbers are still in the Sheet, so the entry stays.
@MainActor
@Test(arguments: ["315x5@7, felt heavy", "315x5@7 felt heavy", "315x5@7 (felt heavy)", "315X5@7", "315lbx5@7"])
func syncKeepsTheEntryOfASetLogWhoseCellTheParseReadsAsACoachNote(notes: String) async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1")])
    let sync = SyncCoordinator(
        client: RetractionStubClient(grid: squatGrid(notes: notes)),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    let entries = try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.map(\.resultText) == ["315x5@7"])
}

/// An Unstructured Set Log has no numbers to match, so it is found as text. Here a filter hides
/// its row, and the entry stays while the text is in the Sheet.
@MainActor
@Test func syncKeepsTheEntryOfAnUnstructuredSetLogStillInTheSheet() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([squatEntry(resultText: "felt heavy", source: "Block 27 · W1 D1")])
    let sync = SyncCoordinator(
        client: RetractionStubClient(
            grid: squatGrid(notes: "Pause 2s at the bottom", extraCells: ["K16": "Felt heavy"]),
            hiddenRows: [15: SheetRowVisibility(hiddenByFilter: true)]
        ),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    let entries = try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.map(\.resultText) == ["felt heavy"])
}

/// A Coach Note in the header sends the Set Log to the row below. With that row cleared, the
/// Coach Note is not the entry's result, so the entry goes.
@MainActor
@Test func syncRetractsTheEntryOfACoachNoteHeadedExerciseWhoseSetLogRowWasCleared() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1")])
    let sync = SyncCoordinator(
        client: RetractionStubClient(grid: squatGrid(notes: "Start w/ 10 sec hold")),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    #expect(try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>()).isEmpty)
}

/// A Prescription Line's own Coach Note sends its Set Log to a spare row. With that row cleared,
/// the entry goes, as it does for a Coach Note in the header.
@MainActor
@Test func syncRetractsTheEntryOfALineWithACoachNoteWhoseSetLogRowWasCleared() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1")])
    let sync = SyncCoordinator(
        client: RetractionStubClient(
            grid: squatGrid(notes: "Brace hard", extraCells: ["D16": "1", "F16": "5", "K16": "Belt on for this one"])
        ),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    #expect(try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>()).isEmpty)
}

/// A Set Log edited into numbers the entry does not hold is a new result. The parse earns the new
/// entry when it can read the cell; when it cannot, the stale entry still goes, because the Sheet no
/// longer holds the result the entry names.
@MainActor
@Test func syncRetractsAStaleEntryWhoseSetLogWasEditedToAnotherValue() async throws {
    let container = try makeRetractionContainer()
    let lookupStore = LastPerformedLookupStore(context: container.mainContext)
    try lookupStore.ingest([squatEntry(resultText: "315x5@7", source: "Block 27 · W1 D1")])
    let sync = SyncCoordinator(
        client: RetractionStubClient(grid: squatGrid(notes: "325x5@7 felt heavy")),
        context: container.mainContext,
        lastPerformed: lookupStore
    )

    #expect(await sync.sync(spreadsheetId: "sid"))

    #expect(try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>()).isEmpty)
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
private func squatGrid(
    notesHeader: String = "Notes",
    notes: String = "",
    extraCells: [String: String] = [:]
) -> SheetGrid {
    let cells: [String: String] = [
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": notesHeader,
        "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE7", "K15": notes
    ]
    return gridFromA1(cells.merging(extraCells) { _, extra in extra }, rows: 24, cols: 30)
}
