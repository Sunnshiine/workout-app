import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private struct WorkoutStoreFixture {
    let store: WorkoutStore
    let container: ModelContainer
}

@MainActor
private func makeStoreBlock() -> Block {
    BlockBuilder.makeBlock(
        from: ParsedBlockModel(
            tabName: "Block 27",
            weeks: [
                ParsedWeek(
                    number: 1,
                    days: (1...4).map { day in
                        ParsedSession(
                            dayNumber: day,
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
                                            prescribedLoad: "RPE8",
                                            percentOneRM: nil
                                        )
                                    ]
                                )
                            ]
                        )
                    }
                )
            ]
        )
    )
}

@MainActor
private func makeStore() throws -> WorkoutStoreFixture {
    let container = try ModelContainer(
        for: Block.self,
        configurations: ModelConfiguration(
            "workout-store-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
    let ctx = container.mainContext
    ctx.insert(makeStoreBlock())
    try ctx.save()
    let store = WorkoutStore(context: ctx)
    store.reload()
    return WorkoutStoreFixture(store: store, container: container)
}

@MainActor
@Test func loadsBlockAndDefaultsDisplayedToCurrent() throws {
    let container = try ModelContainer(for: Block.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let parsed = ParsedBlockModel(
        tabName: "Block 27",
        weeks: (1...1).map { w in
            ParsedWeek(
                number: w,
                days: (1...4).map { d in
                    ParsedSession(dayNumber: d, date: nil, exercises: [])
                }
            )
        }
    )
    ctx.insert(BlockBuilder.makeBlock(from: parsed))
    try ctx.save()

    let store = WorkoutStore(context: ctx)
    store.reload()

    #expect(store.block?.tabName == "Block 27")
    #expect(store.displayedSession?.dayNumber == 1)  // defaults to current
    store.show(week: 1, day: 3)
    #expect(store.displayedSession?.dayNumber == 3)
}

@MainActor
@Test func openExercisesDelegatesToCurrentBlockAndCurrentSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day1 = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 1 })
    let day3 = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 })
    day1.exercises[0].sets.append(
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil, state: .pending)
    )
    day1.exercises[0].sets[0].state = .logged
    day3.exercises[0].sets[0].state = .logged
    store.reload()

    #expect(store.currentSession?.dayNumber == 3)
    #expect(store.openExercises.map { $0.session?.dayNumber } == [1, 2])
}

@MainActor
@Test func showCurrentResetsDisplayedSessionToCurrentSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3 = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 })
    day3.exercises[0].sets[0].state = .logged
    store.reload()

    store.show(week: 1, day: 1)
    #expect(store.displayedSession?.dayNumber == 1)

    store.showCurrent()

    #expect(store.displayedSession?.dayNumber == 3)
    #expect(store.isViewingLiveEdge)
}
