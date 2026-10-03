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
        session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
        dayNumbering: .headerNumber,
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
    #expect(fetched.session.blockTab == "Block 27")
    #expect(fetched.column == .notes)
    #expect(fetched.operation == .upsert)
    #expect(fetched.status == .pending)
    #expect(fetched.expectedCurrentValue == "")

    let durableText = [
        fetched.session.blockTab,
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
        session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
        dayNumbering: .headerNumber,
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

@Test func storedSessionAttributesKeepTheirShippedNamesAndTypes() throws {
    func types(_ type: any PersistentModel.Type, _ names: [String]) throws -> [String: String] {
        let attributes = try #require(Schema([type]).entities.first).attributes
        return Dictionary(
            uniqueKeysWithValues: attributes.filter { names.contains($0.name) }.map { ($0.name, "\($0.valueType)") }
        )
    }

    #expect(
        try types(PendingWrite.self, ["blockTab", "week", "day", "dayNumberingRaw"])
            == ["blockTab": "String", "week": "Int", "day": "Int", "dayNumberingRaw": "Optional<String>"]
    )
    #expect(
        try types(WriteTargetAuditEntry.self, ["blockTab", "week", "day"])
            == ["blockTab": "String", "week": "Int", "day": "Int"]
    )
}
