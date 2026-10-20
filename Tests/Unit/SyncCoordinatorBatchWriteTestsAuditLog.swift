import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func successfulFlushRecordsWriteTargetAuditEntry() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, setIndex: 0, valueToWrite: "185x5@8"))
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: coachNoteHiddenContinuationGrid(),
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    let entry = try #require(entries.first)
    #expect(entries.count == 1)
    #expect(entry.recordedSession.blockTab == "Block 27")
    #expect(entry.recordedSession.address.week == 1)
    #expect(entry.recordedSession.address.day == 1)
    #expect(entry.exerciseName == "Squat")
    #expect(entry.setIndex == 0)
    #expect(entry.column == .notes)
    #expect(entry.selectedA1Target == "'Block 27'!K17")
    #expect(entry.rowScanDetails.contains("Skipped hidden rows: row 16 hidden by user"))
    #expect(entry.rowScanDetails.contains("Selected row 17"))
    #expect(entry.valueCheckOutcome.contains("matched expected"))
    #expect(entry.finalStatus == .succeeded)
}

@MainActor
@Test func conflictFlushRecordsWriteTargetAuditEntryWhenNoWritableRowIsSelected() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, exerciseName: "Bench Press", valueToWrite: "135x5@7"))
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: multiExerciseConflictGrid(),
        rowVisibility: [17: SheetRowVisibility(hiddenByUser: true)]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    let entry = try #require(entries.first)
    #expect(entries.count == 1)
    #expect(entry.exerciseName == "Bench Press")
    #expect(entry.selectedA1Target == nil)
    #expect(entry.rowScanDetails.contains("Skipped hidden rows: row 18 hidden by user"))
    #expect(entry.rowScanDetails.contains("No row selected"))
    #expect(entry.valueCheckOutcome == "Not checked because no target was selected.")
    #expect(entry.finalStatus == .conflict)
}

@MainActor
@Test func selectedTargetConflictRecordsWriterReportedValueCheck() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1))
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: coachNoteHiddenContinuationGrid(firstVisibleLog: "coach edited"),
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    let entry = try #require(entries.first)
    #expect(entries.count == 1)
    #expect(entry.selectedA1Target == "'Block 27'!K17")
    #expect(entry.currentValue == "coach edited")
    #expect(entry.valueCheckOutcome == "Expected '', found 'coach edited'.")
    #expect(entry.finalStatus == .conflict)
}

@MainActor
@Test func writeTargetAuditLogKeepsMostRecentOneHundredEntries() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    for index in 0..<100 {
        ctx.insert(
            WriteTargetAuditEntry(
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                recordedSession: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
                exerciseName: "Old \(index)",
                setIndex: 0,
                column: .notes,
                selectedA1Target: nil,
                rowScanDetails: "old",
                expectedCurrentValue: "",
                currentValue: nil,
                valueCheckOutcome: "old",
                finalStatus: .succeeded,
                message: nil
            )
        )
    }
    ctx.insert(batchPendingWrite(createdAt: 101, valueToWrite: "185x5@8"))
    try ctx.save()
    let client = BatchFlushStubClient(grid: oneSetGrid())
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let entries = try ctx.fetch(
        FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)])
    )
    #expect(entries.count == 100)
    #expect(entries.first?.exerciseName == "Old 1")
    #expect(entries.last?.exerciseName == "Squat")
}
