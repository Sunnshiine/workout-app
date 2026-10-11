import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

/// Logging the only Set of the Replacement Squat queues its Set Log and its Last Set RPE mirror.
/// The fixture's Replacement Sheet must take both in one flush, or a fixture launch that switches
/// to it can never empty its pending-write queue.
@MainActor
@Test func theReplacementFixtureSheetTakesBothWritesOfALoggedSet() async throws {
    let container = try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        LastPerformedEntry.self,
        configurations: ModelConfiguration("replacement-fixture-\(UUID().uuidString)", isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    for (createdAt, column, value) in [(1.0, PendingWriteColumn.notes, "185x5@8"), (2.0, .lastSetRPE, "8")] {
        context.insert(
            PendingWrite(
                createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
                session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
                dayNumbering: .headerNumber,
                exerciseName: "Replacement Squat",
                setIndex: 0,
                column: column,
                operation: .upsert,
                valueToWrite: value,
                expectedCurrentValue: ""
            )
        )
    }
    try context.save()
    let sync = SyncCoordinator(client: UITestFixture.makeSheetsClient(), context: context)

    await sync.flushPending(spreadsheetId: WorkoutFixtureScenarios.replacementSheetId)

    #expect(sync.outcome == SyncOutcome.clear)
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).map(\.statusRaw) == [String]())
}
