import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func makeLocalWorkbookRoundTripContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func localWorkbookPendingWrite(
    createdAt: TimeInterval,
    exerciseName: String = "2-3:1:0 Incline DB BP",
    week: Int = 2,
    day: Int = 1,
    setIndex: Int,
    column: PendingWriteColumn = .notes,
    valueToWrite: String
) -> PendingWrite {
    PendingWrite(
        createdAt: Date(timeIntervalSince1970: createdAt),
        blockTab: "Block 27",
        week: week,
        day: day,
        exerciseName: exerciseName,
        setIndex: setIndex,
        column: column,
        operation: .upsert,
        valueToWrite: valueToWrite,
        expectedCurrentValue: ""
    )
}

private func parsedExercise(
    named name: String,
    from parsed: ParsedBlock,
    week: Int = 2,
    day: Int = 1
) throws -> ParsedExercise {
    try #require(
        parsed.block.weeks.first { $0.number == week }?
            .days.first { $0.dayNumber == day }?
            .exercises.first {
                $0.name == name
            }
    )
}

@MainActor
private func insertVisibleWritableRoundTripWrites(into context: ModelContext) throws {
    let writes = [
        localWorkbookPendingWrite(
            createdAt: 1,
            setIndex: 0,
            valueToWrite: "100x8@6"
        ),
        localWorkbookPendingWrite(
            createdAt: 2,
            setIndex: 1,
            valueToWrite: "105x7@7"
        ),
        localWorkbookPendingWrite(
            createdAt: 3,
            setIndex: 1,
            column: .lastSetRPE,
            valueToWrite: "7"
        ),
        localWorkbookPendingWrite(
            createdAt: 4,
            exerciseName: "0:2:0 Hamstring Curl",
            setIndex: 0,
            valueToWrite: "65x12@8"
        ),
        localWorkbookPendingWrite(
            createdAt: 5,
            exerciseName: "0:2:0 Hamstring Curl",
            setIndex: 0,
            column: .lastSetRPE,
            valueToWrite: "8"
        )
    ]
    for write in writes {
        context.insert(write)
    }
    try context.save()
}

private func assertVisibleWritableRoundTripWorkbook(_ updated: SheetGrid) {
    #expect(updated.cell(row: 40, col: 10) == "AMRAP w/ 0:3:0 BW Push Up")
    #expect(updated.cell(row: 41, col: 10) == "999x1@10")
    #expect(updated.cell(row: 42, col: 10) == "100x8@6, 105x7@7")
    #expect(updated.cell(row: 40, col: 8) == "7")
    #expect(updated.cell(row: 45, col: 10) == "Controlled eccentric")
    #expect(updated.cell(row: 46, col: 10) == "100x1@10")
    #expect(updated.cell(row: 47, col: 10) == "65x12@8")
    #expect(updated.cell(row: 45, col: 8) == "8")
}

private func assertVisibleWritableParsedState(_ parsed: ParsedBlock) throws {
    let incline = try parsedExercise(named: "2-3:1:0 Incline DB BP", from: parsed)
    let inclineFirstSet = try #require(incline.sets.first { $0.index == 0 })
    let inclineSecondSet = try #require(incline.sets.first { $0.index == 1 })
    let hamstringCurl = try parsedExercise(named: "0:2:0 Hamstring Curl", from: parsed)
    let hamstringCurlSet = try #require(hamstringCurl.sets.first)

    #expect(incline.coachNote == "AMRAP w/ 0:3:0 BW Push Up")
    #expect(inclineFirstSet.state == .logged)
    #expect(inclineFirstSet.setLog?.formatted == "100x8@6")
    #expect(inclineSecondSet.state == .logged)
    #expect(inclineSecondSet.setLog?.formatted == "105x7@7")
    #expect(hamstringCurl.coachNote == "Controlled eccentric")
    #expect(hamstringCurlSet.state == .logged)
    #expect(hamstringCurlSet.setLog?.formatted == "65x12@8")
    #expect(parsed.warnings.isEmpty)
}

@MainActor
@Test func localWorkbookRoundTripFlushWritesVisibleRowsAndParsesDomainState() async throws {
    let container = try makeLocalWorkbookRoundTripContainer()
    let context = container.mainContext
    try insertVisibleWritableRoundTripWrites(into: context)

    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": visibleWritableRowRoundTripSnapshot()]
    )
    let sync = SyncCoordinator(client: client, context: context)

    await sync.flushPending(spreadsheetId: "sid")

    let updatedSnapshot = try await client.fetchTabSnapshot(spreadsheetId: "sid", tabName: "Block 27")
    let updated = updatedSnapshot.values
    let parsed = SheetParser().parse(snapshot: updatedSnapshot, tabName: "Block 27")
    let batches = await client.recordedBatches

    assertVisibleWritableRoundTripWorkbook(updated)
    try assertVisibleWritableParsedState(parsed)
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.state == .idle)
    #expect(batches.count == 2)
    #expect(batches[0].map(\.range) == ["'Block 27'!K43"])
    #expect(batches[1].map(\.range) == ["'Block 27'!K43", "'Block 27'!I41", "'Block 27'!K48", "'Block 27'!I46"])
}

@MainActor
@Test func failedLocalWorkbookRoundTripKeepsPendingWritesForRetry() async throws {
    let container = try makeLocalWorkbookRoundTripContainer()
    let context = container.mainContext
    context.insert(
        localWorkbookPendingWrite(
            createdAt: 1,
            setIndex: 0,
            valueToWrite: "100x8@6"
        )
    )
    try context.save()

    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": visibleWritableRowRoundTripSnapshot()],
        failedUpdateRequestNumbers: [1]
    )
    let sync = SyncCoordinator(client: client, context: context)

    await sync.flushPending(spreadsheetId: "sid")

    let updated = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let writes = try context.fetch(FetchDescriptor<PendingWrite>())
    let retry = try #require(writes.first)
    let batches = await client.recordedBatches

    #expect(updated.cell(row: 41, col: 10) == "999x1@10")
    #expect(updated.cell(row: 42, col: 10) == "")
    #expect(writes.count == 1)
    #expect(retry.status == .pending)
    #expect(retry.retryCount == 1)
    #expect(batches.isEmpty)
    #expect(sync.state == .pendingWrites(1))
}
