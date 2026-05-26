import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func loggingContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "logging-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@MainActor
private struct SeededLoggingStore {
    let store: WorkoutStore
    let context: ModelContext
    let firstSet: ExerciseSet
    let container: ModelContainer
}

private func parsedLoggingBlock() -> ParsedBlockModel {
    ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            ParsedWeek(
                number: 1,
                days: [
                    ParsedSession(
                        dayNumber: 1,
                        date: Date(timeIntervalSinceReferenceDate: 100),
                        exercises: [
                            ParsedExercise(
                                name: "Squat",
                                baseName: "Squat",
                                cadence: nil,
                                coachNote: nil,
                                sets: [
                                    ParsedSet(
                                        index: 0,
                                        prescribedReps: "5",
                                        prescribedLoad: "RPE 8",
                                        percentOneRM: nil,
                                        state: .pending,
                                        setLog: nil
                                    ),
                                    ParsedSet(
                                        index: 1,
                                        prescribedReps: "5",
                                        prescribedLoad: "RPE 9",
                                        percentOneRM: nil,
                                        state: .pending,
                                        setLog: nil
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        ]
    )
}

@MainActor
private func seededStore() throws -> SeededLoggingStore {
    let container = try loggingContainer()
    let ctx = container.mainContext
    let block = BlockBuilder.makeBlock(from: parsedLoggingBlock())
    ctx.insert(block)
    try ctx.save()
    let store = WorkoutStore(context: ctx)
    store.reload()
    let set = try #require(
        store.block?.weeks.first?.sessions.first?.exercises.first?.sets.sorted {
            $0.index < $1.index
        }.first
    )
    return SeededLoggingStore(store: store, context: ctx, firstSet: set, container: container)
}

@MainActor
@Test func logSetOptimisticallyUpdatesLocalSetAndQueuesWrite() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}
    let log = SetLog(weight: .pounds(185), reps: 5, rpe: 8)

    try fixture.store.log(fixture.firstSet, as: log)

    #expect(fixture.firstSet.state == .logged)
    #expect(fixture.firstSet.setLog?.formatted == "185x5@8")
    let writes = try fixture.context.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.count == 1)
    #expect(writes[0].column == .notes)
    #expect(writes[0].valueToWrite == "185x5@8")
    #expect(writes[0].expectedCurrentValue == "")
}

@MainActor
@Test func loggingFinalSetQueuesLastSetRPEWrite() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}
    let finalSet = try #require(fixture.firstSet.exercise?.sets.first { $0.index == 1 })

    try fixture.store.log(finalSet, as: SetLog(weight: .pounds(195), reps: 5, rpe: 9))

    let writes = try fixture.context.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.contains { $0.column == .lastSetRPE && $0.valueToWrite == "9" })
}

@MainActor
@Test func deleteSetClearsLocalSetAndQueuesDelete() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}
    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    try fixture.store.deleteLog(for: fixture.firstSet)

    #expect(fixture.firstSet.state == .pending)
    #expect(fixture.firstSet.setLog == nil)
    let pending = try #require(try fixture.context.fetch(FetchDescriptor<PendingWrite>()).last)
    #expect(pending.operation == .delete)
    #expect(pending.expectedCurrentValue == "185x5@8")
}

@MainActor
@Test func logSetUpdatesLastPerformedIndexForExercise() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}

    try fixture.store.log(fixture.firstSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    let index = LastPerformedIndex(context: fixture.context)
    let entry = try #require(index.lookup(exerciseName: "Squat", baseName: "Squat"))
    #expect(entry.result == SetLog(weight: .pounds(185), reps: 5, rpe: 8))
    #expect(entry.performedOn == Date(timeIntervalSinceReferenceDate: 100))
    #expect(entry.source == "Block 27 · W1 D1")
}

@MainActor
@Test func skipSetDoesNotWriteLastPerformedEntry() throws {
    let fixture = try seededStore()
    withExtendedLifetime(fixture.container) {}

    try fixture.store.skip(fixture.firstSet)

    let index = LastPerformedIndex(context: fixture.context)
    #expect(index.lookup(exerciseName: "Squat", baseName: "Squat") == nil)
}
