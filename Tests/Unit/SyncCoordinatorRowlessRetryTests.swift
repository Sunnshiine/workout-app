import SwiftData
import Testing

@testable import WorkoutTracker

private func squatGrid(_ cells: [String: String]) -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "K15": "Coach note"
        ].merging(cells) { _, new in new },
        rows: 24,
        cols: 30
    )
}

@MainActor
private func queueSquatSetLog(in ctx: ModelContext) throws {
    ctx.insert(
        PendingWrite(
            session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
            dayNumbering: .headerNumber,
            exerciseName: "Squat",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "185x5@8",
            expectedCurrentValue: ""
        )
    )
    try ctx.save()
}

@MainActor
@Test func flushWritesASetLogRefusedForWantOfARowOnceTheSheetHasOne() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    try queueSquatSetLog(in: ctx)
    let client = FlushStubClient(grid: squatGrid(["C16": "Bench"]))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).map(\.status) == [.conflict])

    client.grid = squatGrid(["C17": "Bench"])
    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.writes == [SheetCellWrite(tabName: "Block 27", a1: "K16", value: "185x5@8")])
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.outcome == .clear)
}

@MainActor
@Test func flushKeepsASetLogTheSheetRefusedByValueRefusedAfterTheCellChanges() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    try queueSquatSetLog(in: ctx)
    let client = FlushStubClient(grid: squatGrid(["K16": "coach edited", "C17": "Bench"]))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")
    client.grid = squatGrid(["C17": "Bench"])
    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.writes.isEmpty)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).map(\.status) == [.conflict])
}
