import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func makeLocalWorkbookRoundTripContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func localWorkbookPendingWrite(
    createdAt: TimeInterval,
    exerciseName: String = "2-3:1:0 Incline DB BP",
    setIndex: Int,
    column: PendingWriteColumn = .notes,
    valueToWrite: String
) -> PendingWrite {
    PendingWrite(
        createdAt: Date(timeIntervalSince1970: createdAt),
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: exerciseName,
        setIndex: setIndex,
        column: column,
        operation: .upsert,
        valueToWrite: valueToWrite,
        expectedCurrentValue: ""
    )
}

private func parsedInclineDBBenchPress(from parsed: ParsedBlock) throws -> ParsedExercise {
    try #require(
        parsed.block.weeks.first?.days.first?.exercises.first {
            $0.name == "2-3:1:0 Incline DB BP"
        }
    )
}

@MainActor
@Test func localWorkbookRoundTripFlushWritesCoachNoteContinuationLogsAndParsesDomainState() async throws {
    let container = try makeLocalWorkbookRoundTripContainer()
    let context = container.mainContext
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
        )
    ]
    for write in writes {
        context.insert(write)
    }
    try context.save()

    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": coachNoteBenchPressRoundTripGrid()]
    )
    let sync = SyncCoordinator(client: client, context: context)

    await sync.flushPending(spreadsheetId: "sid")

    let updated = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let parsed = SheetParser().parse(grid: updated, tabName: "Block 27")
    let exercise = try parsedInclineDBBenchPress(from: parsed)
    let firstSet = try #require(exercise.sets.first { $0.index == 0 })
    let secondSet = try #require(exercise.sets.first { $0.index == 1 })
    let batches = await client.recordedBatches

    #expect(updated.cell(row: 50, col: 10) == "AMRAP w/ 0:3:0 BW Push Up")
    #expect(updated.cell(row: 51, col: 10) == "100x8@6")
    #expect(updated.cell(row: 52, col: 10) == "105x7@7")
    #expect(updated.cell(row: 50, col: 8) == "7")
    #expect(exercise.coachNote == "AMRAP w/ 0:3:0 BW Push Up")
    #expect(firstSet.state == .logged)
    #expect(firstSet.setLog?.formatted == "100x8@6")
    #expect(secondSet.state == .logged)
    #expect(secondSet.setLog?.formatted == "105x7@7")
    #expect(parsed.warnings.isEmpty)
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.state == .idle)
    #expect(batches.count == 1)
    #expect(batches[0].map(\.range) == ["'Block 27'!K52", "'Block 27'!K53", "'Block 27'!I51"])
}
