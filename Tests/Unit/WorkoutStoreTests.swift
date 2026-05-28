import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private struct WorkoutStoreFixture {
    let store: WorkoutStore
    let container: ModelContainer
}

@MainActor
private func makeStoreBlock(weekCount: Int = 1) -> Block {
    BlockBuilder.makeBlock(
        from: ParsedBlockModel(
            tabName: "Block 27",
            weeks: (1...weekCount).map { week in
                ParsedWeek(
                    number: week,
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
            }
        )
    )
}

@MainActor
private func makeDefaults() throws -> UserDefaults {
    let suiteName = "test.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func makeStore(weekCount: Int = 1, defaults: UserDefaults? = nil) throws -> WorkoutStoreFixture {
    let container = try ModelContainer(
        for: Block.self,
        configurations: ModelConfiguration(
            "workout-store-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
    let ctx = container.mainContext
    ctx.insert(makeStoreBlock(weekCount: weekCount))
    try ctx.save()
    let store = try WorkoutStore(context: ctx, defaults: defaults ?? makeDefaults())
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

    let store = try WorkoutStore(context: ctx, defaults: makeDefaults())
    store.reload()

    #expect(store.block?.tabName == "Block 27")
    #expect(store.displayedSession?.dayNumber == 1)  // defaults to current
    store.show(week: 1, day: 3)
    #expect(store.displayedSession?.dayNumber == 3)
}

@MainActor
@Test func openExercisesDelegatesToCurrentBlockAndCurrentSession() throws {
    let container = try ModelContainer(
        for: Block.self,
        configurations: ModelConfiguration(
            "open-exercises-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    context.insert(WorkoutScenarios.openExercises().block)
    try context.save()

    let store = try WorkoutStore(context: context, defaults: makeDefaults())
    store.reload()

    #expect(store.currentSession?.dayNumber == 3)
    #expect(store.openExercises.map(\.name) == ["Back Squat", "Bench Press"])
}

@MainActor
@Test func reloadPreservesDisplayedSessionWhenStillPresent() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.show(week: 1, day: 3)
    store.reload()

    #expect(store.displayedSession?.week?.number == 1)
    #expect(store.displayedSession?.dayNumber == 3)
}

@MainActor
@Test func reloadAdvancesDisplayedSessionWhenViewingCurrentSession() throws {
    let fixture = try makeStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 }?.exercises[0].sets[0])

    day3Set.state = .logged
    store.reload()

    #expect(store.currentSession?.dayNumber == 3)
    #expect(store.displayedSession?.dayNumber == 3)
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

@MainActor
@Test func moveOnAdvancesCurrentSessionAndDisplayedSession() throws {
    let fixture = try makeStore(defaults: makeDefaults())
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()

    #expect(store.currentSession?.week?.number == 1)
    #expect(store.currentSession?.dayNumber == 2)
    #expect(store.displayedSession?.week?.number == 1)
    #expect(store.displayedSession?.dayNumber == 2)
}

@MainActor
@Test func requestingMoveOnCelebrationCapturesCurrentSessionWithoutAdvancing() throws {
    let fixture = try makeStore(defaults: makeDefaults())
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.requestMoveOnCelebration()

    #expect(store.moveOnCelebrationSession?.week?.number == 1)
    #expect(store.moveOnCelebrationSession?.dayNumber == 1)
    #expect(store.currentSession?.week?.number == 1)
    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.displayedSession?.week?.number == 1)
    #expect(store.displayedSession?.dayNumber == 1)
}

@MainActor
@Test func dismissingMoveOnCelebrationAdvancesFromCapturedSession() throws {
    let fixture = try makeStore(defaults: makeDefaults())
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.requestMoveOnCelebration()
    store.dismissMoveOnCelebration()

    #expect(store.moveOnCelebrationSession == nil)
    #expect(store.currentSession?.week?.number == 1)
    #expect(store.currentSession?.dayNumber == 2)
    #expect(store.displayedSession?.week?.number == 1)
    #expect(store.displayedSession?.dayNumber == 2)
}

@MainActor
@Test func reachingZeroLeftDoesNotShowCelebrationOrAdvanceCurrentSession() throws {
    let fixture = try makeStore(defaults: makeDefaults())
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let currentSet = try #require(store.currentSession?.exercises[0].sets[0])

    currentSet.state = .logged
    store.reload()

    let currentSession = try #require(store.currentSession)
    let presentation = SessionProgressHeaderPresentation(session: currentSession)
    #expect(presentation.remainingSetCount == 0)
    #expect(store.moveOnCelebrationSession == nil)
    #expect(store.currentSession?.week?.number == 1)
    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.displayedSession?.week?.number == 1)
    #expect(store.displayedSession?.dayNumber == 1)
}

@MainActor
@Test func moveOnAdvancePersistsAcrossReload() throws {
    let fixture = try makeStore(defaults: makeDefaults())
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()
    store.reload()

    #expect(store.currentSession?.dayNumber == 2)
    #expect(store.displayedSession?.dayNumber == 2)
}

@MainActor
@Test func repeatedMoveOnsOverwriteStoredAdvance() throws {
    let fixture = try makeStore(defaults: makeDefaults())
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()
    store.moveOn()

    #expect(store.currentSession?.dayNumber == 3)
    #expect(store.displayedSession?.dayNumber == 3)
}

@MainActor
@Test func moveOnCrossesWeekBoundaryAndDropsPriorWeekOpenExercises() throws {
    let fixture = try makeStore(weekCount: 2, defaults: makeDefaults())
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()
    store.moveOn()
    store.moveOn()
    store.moveOn()

    #expect(store.currentSession?.week?.number == 2)
    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.openExercises.isEmpty)
}

@MainActor
@Test func loggedProgressPastStoredAdvanceBecomesCurrentSession() throws {
    let fixture = try makeStore(defaults: makeDefaults())
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let day3Set = try #require(store.block?.weeks.first?.sessions.first { $0.dayNumber == 3 }?.exercises[0].sets[0])

    store.moveOn()
    try store.log(day3Set, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    #expect(store.currentSession?.dayNumber == 3)
}

@MainActor
@Test func canMoveOnIsFalseOnLastSession() throws {
    let fixture = try makeStore(weekCount: 4, defaults: makeDefaults())
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store
    let finalSet = try #require(
        store.block?.weeks.first { $0.number == 4 }?.sessions.first { $0.dayNumber == 4 }?.exercises[0].sets[0]
    )

    finalSet.state = .logged
    store.reload()

    #expect(store.currentSession?.week?.number == 4)
    #expect(store.currentSession?.dayNumber == 4)
    #expect(!store.canMoveOn)
}
