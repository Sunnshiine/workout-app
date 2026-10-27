import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private enum SchemaWithFullName: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [LastPerformedEntry.self] }

    @Model
    final class LastPerformedEntry {
        var fullName: String
        var baseName: String
        var resultText: String = ""
        var performedOn: Date
        var source: String

        init(fullName: String, resultText: String, source: String) {
            self.fullName = fullName
            baseName = fullName
            self.resultText = resultText
            performedOn = Date(timeIntervalSinceReferenceDate: 100)
            self.source = source
        }
    }
}

@MainActor
@Test func anExerciseHistoryEntryAnEarlierBuildStoredOpensWithItsEnteredName() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("store.sqlite")
    do {
        let schema = Schema(versionedSchema: SchemaWithFullName.self)
        let earlier = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        earlier.mainContext.insert(
            SchemaWithFullName.LastPerformedEntry(fullName: "Squat", resultText: "185x5@8", source: "Block 26 · W3 D1")
        )
        try earlier.mainContext.save()
    }

    let container = try ModelContainer(for: LastPerformedEntry.self, configurations: ModelConfiguration(url: url))
    let store = LastPerformedLookupStore(context: container.mainContext)

    let match = try #require(store.snapshot.lookup(for: "Squat"))
    #expect(match.resultText == "185x5@8")
    #expect(match.sourceText == "Block 26 · W3 D1")
    withExtendedLifetime(container) {}
}
