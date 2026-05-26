import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func loggingContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        configurations: ModelConfiguration(
            "logging-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@MainActor
private func seededStore() throws -> (WorkoutStore, ModelContext, ExerciseSet, ModelContainer) {
    let container = try loggingContainer()
    let ctx = container.mainContext
    let parsed = ParsedBlockModel(
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
    let block = BlockBuilder.makeBlock(from: parsed)
    ctx.insert(block)
    try ctx.save()
    let store = WorkoutStore(context: ctx)
    store.reload()
    let set = try #require(
        store.block?.weeks.first?.sessions.first?.exercises.first?.sets.sorted {
            $0.index < $1.index
        }.first
    )
    return (store, ctx, set, container)
}

@MainActor
@Test func logSetOptimisticallyUpdatesLocalSetAndQueuesWrite() throws {
    let (store, ctx, set, _container) = try seededStore()
    withExtendedLifetime(_container) {}
    let log = SetLog(weight: .pounds(185), reps: 5, rpe: 8)

    try store.log(set, as: log)

    #expect(set.state == .logged)
    #expect(set.setLog?.formatted == "185x5@8")
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.count == 1)
    #expect(writes[0].column == .notes)
    #expect(writes[0].valueToWrite == "185x5@8")
    #expect(writes[0].expectedCurrentValue == "")
}

@MainActor
@Test func loggingFinalSetQueuesLastSetRPEWrite() throws {
    let (store, ctx, firstSet, _container) = try seededStore()
    withExtendedLifetime(_container) {}
    let finalSet = try #require(firstSet.exercise?.sets.first { $0.index == 1 })

    try store.log(finalSet, as: SetLog(weight: .pounds(195), reps: 5, rpe: 9))

    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.contains { $0.column == .lastSetRPE && $0.valueToWrite == "9" })
}

@MainActor
@Test func deleteSetClearsLocalSetAndQueuesDelete() throws {
    let (store, ctx, set, _container) = try seededStore()
    withExtendedLifetime(_container) {}
    try store.log(set, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    try store.deleteLog(for: set)

    #expect(set.state == .pending)
    #expect(set.setLog == nil)
    let pending = try #require(try ctx.fetch(FetchDescriptor<PendingWrite>()).last)
    #expect(pending.operation == .delete)
    #expect(pending.expectedCurrentValue == "185x5@8")
}
