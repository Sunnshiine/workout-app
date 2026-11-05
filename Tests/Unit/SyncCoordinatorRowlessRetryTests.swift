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

@MainActor
private func parkedWrite(
    exercise: String,
    setIndex: Int = 0,
    column: PendingWriteColumn = .notes,
    value: String,
    refusal: String,
    in ctx: ModelContext
) throws {
    let write = PendingWrite(
        session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
        dayNumbering: .headerNumber,
        exerciseName: exercise,
        setIndex: setIndex,
        column: column,
        operation: .upsert,
        valueToWrite: value,
        expectedCurrentValue: ""
    )
    write.markConflict(refusal)
    ctx.insert(write)
    try ctx.save()
}

private let shippedNoRowRefusal = """
    Set 1 for Squat cannot be written because existing header Notes prevent writing there, and no safe \
    Set row exists before the next Exercise. Add a row in the Sheet, clear or migrate the existing \
    header note, then sync again.
    """

/// These strings are what a shipped build stored on the athlete's phone, so rewording the refusal
/// must keep matching them.
@MainActor
@Test func flushRetriesASetLogAndItsLastSetRPEParkedByAShippedBuild() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    try parkedWrite(exercise: "Squat", value: "185x5@8", refusal: shippedNoRowRefusal, in: ctx)
    try parkedWrite(
        exercise: "Squat",
        column: .lastSetRPE,
        value: "8",
        refusal: "Last Set RPE was not written because the paired Set Log failed: Squat: \(shippedNoRowRefusal)",
        in: ctx
    )
    let client = FlushStubClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
                "C15": "Squat", "D15": "1", "K15": "Coach note", "C17": "Bench"
            ],
            rows: 24,
            cols: 30
        )
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(
        client.writes == [
            SheetCellWrite(tabName: "Block 27", a1: "K16", value: "185x5@8"),
            SheetCellWrite(tabName: "Block 27", a1: "I15", value: "8")
        ]
    )
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
}

@MainActor
@Test func flushRetriesASetLogParkedBecauseItsSetRowWasNotFound() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    try parkedWrite(
        exercise: "Squat",
        setIndex: 1,
        value: "185x5@8",
        refusal: "Set 2 row was not found for Squat",
        in: ctx
    )
    let client = FlushStubClient(grid: squatGrid(["K15": "", "D15": "1", "C18": "Bench"]))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.writes.count == 1)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
}

@MainActor
@Test func flushLeavesAWriteParkedForAnotherReasonParked() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    try parkedWrite(exercise: "Squat", value: "185x5@8", refusal: "Squat was not found in the sheet", in: ctx)
    let client = FlushStubClient(grid: squatGrid(["C17": "Bench"]))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.writes.isEmpty)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).map(\.status) == [.conflict])
}

@MainActor
@Test func flushLeavesALastSetRPEParkedWithASetLogRefusedByValueParked() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    try parkedWrite(
        exercise: "Squat",
        column: .lastSetRPE,
        value: "8",
        refusal: "Last Set RPE was not written because the paired Set Log failed: Squat: Expected '', found 'x'",
        in: ctx
    )
    let client = FlushStubClient(grid: squatGrid(["I14": "Last set RPE", "C17": "Bench"]))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.writes.isEmpty)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).map(\.status) == [.conflict])
}
