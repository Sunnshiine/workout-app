import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func lastPerformedContainer() throws -> ModelContainer {
    try ModelContainer(
        for: LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "last-performed-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@MainActor
@Test func lastPerformedLookupFindsExactCadenceMatch() throws {
    let container = try lastPerformedContainer()
    let context = container.mainContext
    let index = LastPerformedIndex(context: context)
    let entry = LastPerformedEntry(
        fullName: "2-3:1:0 BB RDL",
        baseName: "BB RDL",
        result: SetLog(weight: .pounds(185), reps: 7, rpe: 6),
        performedOn: Date(timeIntervalSinceReferenceDate: 100),
        source: "Block 26 · W3 D1"
    )
    context.insert(entry)
    try context.save()

    let match = try #require(index.lookup(exerciseName: "2-3:1:0 BB RDL", baseName: "BB RDL"))

    #expect(match.result == SetLog(weight: .pounds(185), reps: 7, rpe: 6))
    #expect(match.source == "Block 26 · W3 D1")
    withExtendedLifetime(container) {}
}

@MainActor
@Test func lastPerformedLookupFallsBackToNewestBaseNameMatch() throws {
    let container = try lastPerformedContainer()
    let context = container.mainContext
    let index = LastPerformedIndex(context: context)
    context.insert(
        LastPerformedEntry(
            fullName: "1:0:1 BB RDL",
            baseName: "BB RDL",
            result: SetLog(weight: .pounds(175), reps: 7, rpe: 6),
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 25 · W4 D1"
        )
    )
    context.insert(
        LastPerformedEntry(
            fullName: "2-3:1:0 BB RDL",
            baseName: "BB RDL",
            result: SetLog(weight: .pounds(185), reps: 7, rpe: 7),
            performedOn: Date(timeIntervalSinceReferenceDate: 200),
            source: "Block 26 · W3 D1"
        )
    )
    try context.save()

    let match = try #require(index.lookup(exerciseName: "3:1:0 BB RDL", baseName: "BB RDL"))

    #expect(match.result == SetLog(weight: .pounds(185), reps: 7, rpe: 7))
    #expect(match.source == "Block 26 · W3 D1")
    withExtendedLifetime(container) {}
}

@MainActor
@Test func lastPerformedLookupReturnsNilWhenNoHistoryExists() throws {
    let container = try lastPerformedContainer()
    let index = LastPerformedIndex(context: container.mainContext)

    let match = index.lookup(exerciseName: "Bench Press", baseName: "Bench Press")

    #expect(match == nil)
    withExtendedLifetime(container) {}
}

@MainActor
@Test func lastPerformedIngestIsIdempotentByFullName() throws {
    let container = try lastPerformedContainer()
    let context = container.mainContext
    let index = LastPerformedIndex(context: context)
    let entry = LastPerformedEntry(
        fullName: "BB RDL",
        baseName: "BB RDL",
        result: SetLog(weight: .pounds(185), reps: 7, rpe: 6),
        performedOn: Date(timeIntervalSinceReferenceDate: 100),
        source: "Block 26 · W3 D1"
    )

    try index.ingest([entry])
    try index.ingest([
        LastPerformedEntry(
            fullName: "BB RDL",
            baseName: "BB RDL",
            result: SetLog(weight: .pounds(185), reps: 7, rpe: 6),
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 26 · W3 D1"
        )
    ])

    let entries = try context.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.count == 1)
    #expect(entries[0].result == SetLog(weight: .pounds(185), reps: 7, rpe: 6))
    withExtendedLifetime(container) {}
}

@MainActor
@Test func lastPerformedIngestAppendsDistinctSessionsOfTheSameExercise() throws {
    let container = try lastPerformedContainer()
    let context = container.mainContext
    let index = LastPerformedIndex(context: context)

    try index.ingest([
        LastPerformedEntry(
            fullName: "Squat",
            baseName: "Squat",
            result: SetLog(weight: .pounds(205), reps: 5, rpe: 8),
            performedOn: Date(timeIntervalSinceReferenceDate: 200),
            source: "Block 27 · W2 D1"
        ),
        LastPerformedEntry(
            fullName: "Squat",
            baseName: "Squat",
            result: SetLog(weight: .pounds(185), reps: 5, rpe: 7),
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 26 · W4 D1"
        )
    ])

    let entries = try context.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.count == 2)
    #expect(Set(entries.map(\.source)) == ["Block 27 · W2 D1", "Block 26 · W4 D1"])

    // Last Performed remains the most-recent entry.
    let match = try #require(index.lookup(exerciseName: "Squat", baseName: "Squat"))
    #expect(match.result == SetLog(weight: .pounds(205), reps: 5, rpe: 8))
    #expect(match.source == "Block 27 · W2 D1")
    withExtendedLifetime(container) {}
}

@MainActor
@Test func lastPerformedIngestDedupsOnNameAndSourceAcrossRepeatedIngests() throws {
    let container = try lastPerformedContainer()
    let context = container.mainContext
    let index = LastPerformedIndex(context: context)

    let entry = {
        LastPerformedEntry(
            fullName: "Squat",
            baseName: "Squat",
            result: SetLog(weight: .pounds(205), reps: 5, rpe: 8),
            performedOn: Date(timeIntervalSinceReferenceDate: 200),
            source: "Block 27 · W2 D1"
        )
    }

    // Ingesting the same tab three times must not accumulate duplicates.
    try index.ingest([entry()])
    try index.ingest([entry()])
    try index.ingest([entry(), entry()])

    let entries = try context.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.count == 1)
    withExtendedLifetime(container) {}
}

@MainActor
@Test func lastPerformedIngestPreservesExistingSeededRows() throws {
    let container = try lastPerformedContainer()
    let context = container.mainContext
    let index = LastPerformedIndex(context: context)

    // A pre-existing (seeded) row from the former last_performed store.
    context.insert(
        LastPerformedEntry(
            fullName: "Squat",
            baseName: "Squat",
            result: SetLog(weight: .pounds(185), reps: 5, rpe: 7),
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 26 · W4 D1"
        )
    )
    try context.save()

    try index.ingest([
        LastPerformedEntry(
            fullName: "Squat",
            baseName: "Squat",
            result: SetLog(weight: .pounds(205), reps: 5, rpe: 8),
            performedOn: Date(timeIntervalSinceReferenceDate: 200),
            source: "Block 27 · W2 D1"
        )
    ])

    let entries = try context.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.count == 2)
    #expect(Set(entries.map(\.source)) == ["Block 26 · W4 D1", "Block 27 · W2 D1"])
    withExtendedLifetime(container) {}
}

@MainActor
@Test func lastPerformedIngestDedupsWhenDatesDegradeToDistantPast() throws {
    let container = try lastPerformedContainer()
    let context = container.mainContext
    let index = LastPerformedIndex(context: context)

    let entry = {
        LastPerformedEntry(
            fullName: "Standing Calve Raises",
            baseName: "Standing Calve Raises",
            resultText: "25x12, 12",
            performedOn: .distantPast,
            source: "Block 27 · W1 D1"
        )
    }

    try index.ingest([entry()])
    try index.ingest([entry()])

    let entries = try context.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.count == 1)
    #expect(entries[0].performedOn == .distantPast)
    withExtendedLifetime(container) {}
}

@MainActor
@Test func lastPerformedIngestKeepsNewestEntryForFullName() throws {
    let container = try lastPerformedContainer()
    let context = container.mainContext
    let index = LastPerformedIndex(context: context)
    try index.ingest([
        LastPerformedEntry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            result: SetLog(weight: .pounds(225), reps: 5, rpe: 8),
            performedOn: Date(timeIntervalSinceReferenceDate: 200),
            source: "Block 27 · W1 D1"
        )
    ])

    try index.ingest([
        LastPerformedEntry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            result: SetLog(weight: .pounds(205), reps: 5, rpe: 7),
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 26 · W4 D1"
        )
    ])

    let match = try #require(index.lookup(exerciseName: "Bench Press", baseName: "Bench Press"))
    #expect(match.result == SetLog(weight: .pounds(225), reps: 5, rpe: 8))
    #expect(match.source == "Block 27 · W1 D1")
    withExtendedLifetime(container) {}
}

@MainActor
@Test func unstructuredOnlyExerciseSurfacesALastPerformedLine() throws {
    let container = try lastPerformedContainer()
    let context = container.mainContext
    let index = LastPerformedIndex(context: context)

    // An Exercise completed only through Unstructured Set Logs — today this leaves the
    // Last Performed line blank; ADR-0012 makes it completion evidence rendered as the
    // raw entered text. This exercises the full extract → ingest → lookup path.
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            ParsedWeek(
                number: 1,
                days: [
                    ParsedSession(
                        dayNumber: 1,
                        date: nil,
                        exercises: [
                            ParsedExercise(
                                name: "Standing Calve Raises",
                                baseName: "Standing Calve Raises",
                                cadence: nil,
                                coachNote: nil,
                                sets: [
                                    ParsedSet(
                                        index: 0,
                                        prescribedReps: "12",
                                        prescribedLoad: "RPE 8",
                                        percentOneRM: nil,
                                        state: .logged,
                                        unstructuredSetLog: "a few sets of 12"
                                    ),
                                    ParsedSet(
                                        index: 1,
                                        prescribedReps: "12",
                                        prescribedLoad: "RPE 8",
                                        percentOneRM: nil,
                                        state: .logged,
                                        unstructuredSetLog: "felt easy"
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        ]
    )

    try index.ingest(LastPerformedExtractor.entries(from: block))

    let line = try #require(
        index.snapshot().lookup(exerciseName: "Standing Calve Raises", baseName: "Standing Calve Raises")
    )
    #expect(line.resultText == "a few sets of 12, felt easy")
    withExtendedLifetime(container) {}
}

@MainActor
@Test func lastPerformedSnapshotPreservesCadencePriorityAndBaseFallback() throws {
    let container = try lastPerformedContainer()
    let context = container.mainContext
    let index = LastPerformedIndex(context: context)
    try index.ingest([
        LastPerformedEntry(
            fullName: "1:0:1 BB RDL",
            baseName: "BB RDL",
            result: SetLog(weight: .pounds(175), reps: 7, rpe: 6),
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "Block 25 · W4 D1"
        ),
        LastPerformedEntry(
            fullName: "2-3:1:0 BB RDL",
            baseName: "BB RDL",
            result: SetLog(weight: .pounds(185), reps: 7, rpe: 7),
            performedOn: Date(timeIntervalSinceReferenceDate: 200),
            source: "Block 26 · W3 D1"
        )
    ])

    let lookup = index.snapshot()

    let exact = try #require(lookup.lookup(exerciseName: "2-3:1:0 BB RDL", baseName: "BB RDL"))
    #expect(exact.resultText == "185x7@7")
    #expect(exact.sourceText == "Block 26 · W3 D1")
    let fallback = try #require(lookup.lookup(exerciseName: "3:1:0 BB RDL", baseName: "BB RDL"))
    #expect(fallback.resultText == "185x7@7")
    #expect(fallback.sourceText == "Block 26 · W3 D1")
    #expect(lookup.lookup(exerciseName: "Bench Press", baseName: "Bench Press") == nil)
    withExtendedLifetime(container) {}
}
