import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func pendingWritePersistsSemanticTargetAndLock() throws {
    let container = try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext
    let write = PendingWrite(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )
    ctx.insert(write)
    try ctx.save()

    let fetched = try #require(try ctx.fetch(FetchDescriptor<PendingWrite>()).first)
    #expect(fetched.blockTab == "Block 27")
    #expect(fetched.column == .notes)
    #expect(fetched.operation == .upsert)
    #expect(fetched.status == .pending)
    #expect(fetched.expectedCurrentValue == "")

    let durableText = [
        fetched.blockTab,
        fetched.exerciseName,
        fetched.columnRaw,
        fetched.operationRaw,
        fetched.valueToWrite,
        fetched.expectedCurrentValue,
        fetched.statusRaw,
        fetched.lastError
    ].compactMap { $0 }
    #expect(durableText.allSatisfy { !$0.contains("!") })
    #expect(durableText.allSatisfy { $0.range(of: #"[A-Z]+[0-9]+"#, options: .regularExpression) == nil })
}

@MainActor
@Test func pendingWriteConflictStatusRoundTrips() throws {
    let write = PendingWrite(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .delete,
        valueToWrite: nil,
        expectedCurrentValue: "185x5@8"
    )

    write.markConflict("Expected 185x5@8, found 190x5@9")

    #expect(write.status == .conflict)
    #expect(write.lastError == "Expected 185x5@8, found 190x5@9")
}
