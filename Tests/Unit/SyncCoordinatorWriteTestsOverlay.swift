import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func syncOverlaysStillPendingWritesOntoFreshBlock() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
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
    let client = FlushStubClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1", "K15": "Coach note", "K16": "coach edited"
            ],
            rows: 24,
            cols: 30
        )
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.sync(spreadsheetId: "sid")

    let block = try #require(try ctx.fetch(FetchDescriptor<Block>()).first)
    let week = try #require(block.weeks.first { $0.number == 1 })
    let session = try #require(week.sessions.first { $0.dayNumber == 1 })
    let exercise = try #require(session.exercises.first { $0.exerciseName == "Squat" })
    let set = try #require(exercise.sets.first { $0.index == 0 })
    #expect(set.state == .logged)
    #expect(set.setLog?.formatted == "185x5@8")
}

@MainActor
@Test func syncOverlaysAQueuedDeleteAsAPendingSet() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(queuedSquatNotesWrite(setIndex: 0, operation: .delete, value: nil))
    try ctx.save()
    let sync = SyncCoordinator(client: FlushStubClient(grid: overlayGrid(notes: "185x5@8")), context: ctx)

    await sync.sync(spreadsheetId: "sid")

    let set = try #require(try overlaidSquatSet(index: 0, in: ctx))
    #expect(set.state == .pending)
    #expect(set.setLog == nil)
    #expect(set.loggedAt == nil)
}

@MainActor
@Test func syncOverlaysAQueuedSkipTokenAsASkippedSet() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(queuedSquatNotesWrite(setIndex: 0, operation: .upsert, value: "skip"))
    try ctx.save()
    let sync = SyncCoordinator(client: FlushStubClient(grid: overlayGrid(notes: "185x5@8")), context: ctx)

    await sync.sync(spreadsheetId: "sid")

    let set = try #require(try overlaidSquatSet(index: 0, in: ctx))
    #expect(set.state == .skipped)
    #expect(set.setLog == nil)
    #expect(set.loggedAt == nil)
}

@MainActor
@Test func syncOverlaysAStillPendingSetLogOverAnUnstructuredSetLogWithoutKeepingTheFreeText() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let write = PendingWrite(
        session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
        dayNumbering: .headerNumber,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: "felt heavy"
    )
    ctx.insert(write)
    try ctx.save()
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "K15": "Coach note", "K16": "felt heavy"
        ],
        rows: 24,
        cols: 30
    )
    let client = FlushStubClient(grid: grid)
    client.shouldFailUpdates = true
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.sync(spreadsheetId: "sid")

    let set = try #require(try overlaidSquatSet(index: 0, in: ctx))
    #expect(write.status == .pending)
    #expect(set.state == .logged)
    #expect(set.setLog?.formatted == "185x5@8")
    #expect(set.unstructuredSetLog == nil)
}

@MainActor
@Test func syncIgnoresAQueuedWriteWhoseSetIsAbsentFromTheFreshBlock() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(queuedSquatNotesWrite(setIndex: 9, operation: .delete, value: nil))
    try ctx.save()
    let sync = SyncCoordinator(client: FlushStubClient(grid: overlayGrid(notes: "185x5@8")), context: ctx)

    await sync.sync(spreadsheetId: "sid")

    let set = try #require(try overlaidSquatSet(index: 0, in: ctx))
    #expect(set.state == .logged)
    #expect(set.setLog?.formatted == "185x5@8")
}

/// The mismatched `expectedCurrentValue` makes the flush record a conflict, which is what leaves the
/// write queued for the overlay to replay.
@MainActor
private func queuedSquatNotesWrite(
    dayNumbering: DayNumbering = .headerNumber,
    setIndex: Int,
    operation: PendingWriteOperation,
    value: String?
) -> PendingWrite {
    PendingWrite(
        session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
        dayNumbering: dayNumbering,
        exerciseName: "Squat",
        setIndex: setIndex,
        column: .notes,
        operation: operation,
        valueToWrite: value,
        expectedCurrentValue: "a value the sheet does not hold"
    )
}

func overlayGrid(notes: String) -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "K15": notes
        ],
        rows: 24,
        cols: 30
    )
}

@MainActor
private func overlaidSquatSet(index: Int, in ctx: ModelContext) throws -> ExerciseSet? {
    try ctx.fetch(FetchDescriptor<Block>()).first?
        .weeks.first { $0.number == 1 }?
        .sessions.first { $0.dayNumber == 1 }?
        .exercises.first { $0.exerciseName == "Squat" }?
        .sets.first { $0.index == index }
}
