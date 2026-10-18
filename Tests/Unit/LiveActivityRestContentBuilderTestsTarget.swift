import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func liveActivityContentTargetsNextPendingSetInSameExerciseAndCountsDisplayedExercisePendingSets() throws {
    let startDate = Date(timeIntervalSinceReferenceDate: 1_000)
    let endDate = Date(timeIntervalSinceReferenceDate: 1_090)
    let exercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged, .pending, .pending])
    let session = makeSingleSession(exercises: [exercise])
    let loggedSet = try #require(exercise.sets.first { $0.index == 0 })

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: startDate,
            restEndDate: endDate
        )
    )

    #expect(content.exerciseName == "Bench Press")
    #expect(content.prescribedReps == "5")
    #expect(content.prescribedLoad == "RPE 8")
    #expect(content.setsDone == 1)
    #expect(content.setsTotal == 3)
    #expect(content.setsLeft == 2)
    #expect(content.setsLeftText == "2 sets left")
    #expect(content.restStartDate == startDate)
    #expect(content.restEndDate == endDate)
    #expect(content.target?.setID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
    #expect(content.target?.session == SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)))
}

@MainActor
@Test func liveActivityContentTargetsNextExercisesFirstPendingSet() throws {
    let squat = makeExercise(name: "Back Squat", order: 0, setStates: [.logged])
    let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending, .pending])
    let session = makeSingleSession(exercises: [squat, bench])
    let loggedSet = try #require(squat.sets.first)

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(content.exerciseName == "Bench Press")
    #expect(content.prescribedLoad == "RPE 7")
    #expect(content.setsLeftText == "2 sets left")
}

@MainActor
@Test func liveActivityUpNextSkipsSettledSetsToTheNextPendingSetInOrder() throws {
    // The rest widget's "up next" walks past the just-Logged Set and a following
    // Skipped Set to the next Pending Set — the third Back Squat Set — rather
    // than jumping to the later Exercises that also hold Pending Sets.
    let squat = makeExercise(name: "Back Squat", order: 0, setStates: [.logged, .skipped, .pending])
    let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending, .logged])
    let row = makeExercise(name: "DB Row", order: 2, setStates: [.pending])
    let session = makeSingleSession(exercises: [squat, bench, row])
    let loggedSet = try #require(squat.sets.first { $0.index == 0 })

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(content.target?.setID == ActiveSetID(exerciseOrder: 0, setIndex: 2))
    #expect(content.exerciseName == "Back Squat")
}

@MainActor
@Test func liveActivityContentNamesTheExerciseByItsBaseNameWithoutTheCadence() throws {
    // PRODUCT.md, Hide the spreadsheet: the lock screen reads the name the stage reads, never the
    // coach's tempo prefix (#987, the twin of #815).
    let rdl = Exercise(name: ExerciseName(entered: "2-3:1:0 BB RDL"), coachNote: nil)
    rdl.sets = [
        ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "Drop 17.5%", percentOneRM: nil, state: .logged),
        ExerciseSet(index: 1, prescribedReps: "8", prescribedLoad: "Drop 17.5%", percentOneRM: nil, state: .pending)
    ]
    let session = makeSingleSession(exercises: [rdl])
    let loggedSet = try #require(rdl.sets.first { $0.index == 0 })

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(content.exerciseName == "BB RDL")
}

@MainActor
@Test func liveActivityContentUsesSupersetAlternationAndCountsDisplayedExerciseOnly() throws {
    let squat = makeExercise(name: "Back Squat", order: 0, setStates: [.logged, .pending])
    let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending, .pending, .pending])
    let row = makeExercise(name: "DB Row", order: 2, setStates: [.pending])
    let session = makeSingleSession(exercises: [squat, bench, row])
    let loggedSet = try #require(squat.sets.first { $0.index == 0 })
    let supersetState = SupersetState()
    #expect(supersetState.createSuperset(with: [squat, bench], in: session))

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            supersetState: supersetState,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(content.exerciseName == "Bench Press")
    #expect(content.prescribedLoad == "RPE 7")
    #expect(content.setsDone == 0)
    #expect(content.setsTotal == 3)
    #expect(content.setsLeftText == "3 sets left")
}

@MainActor
@Test func liveActivityContentSuppressesWhenNoPendingTargetExists() throws {
    let exercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged])
    let session = makeSingleSession(exercises: [exercise])
    let loggedSet = try #require(exercise.sets.first)

    let content = LiveActivityRestContentBuilder.content(
        afterLogging: loggedSet,
        in: session,
        restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
        restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
    )

    #expect(content == nil)
}

@MainActor
@Test func liveActivityTargetValidationKeepsMatchingCurrentDisplayedPendingSet() throws {
    let exercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged, .pending])
    let session = makeSingleSession(exercises: [exercise])
    let loggedSet = try #require(exercise.sets.first { $0.index == 0 })
    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: .atLiveEdge(currentSession: session)) == false)
}

@MainActor
@Test func liveActivityTargetValidationEndsWhenTargetSetIsNoLongerPending() throws {
    let exercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged, .pending])
    let session = makeSingleSession(exercises: [exercise])
    let loggedSet = try #require(exercise.sets.first { $0.index == 0 })
    let targetSet = try #require(exercise.sets.first { $0.index == 1 })
    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: session,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    targetSet.state = .logged

    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: .atLiveEdge(currentSession: session)))
}

@MainActor
@Test func liveActivityTargetValidationKeepsRestWhenASecondInstanceBacksTheSameSession() throws {
    let container = try makeStoredWeek()
    defer { withExtendedLifetime(container) {} }
    let viewed = try #require(try storedWeekSession(dayNumber: 1, in: container.mainContext))
    let loggedSet = try #require(viewed.exercises.first?.sets.first { $0.index == 0 })
    loggedSet.state = .logged
    try container.mainContext.save()
    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: viewed,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    let secondInstance = try #require(try storedWeekSession(dayNumber: 1, in: ModelContext(container)))
    #expect(secondInstance !== viewed)
    #expect(secondInstance.persistentModelID == viewed.persistentModelID)

    #expect(
        LiveActivityInvalidationPolicy.shouldEnd(
            content,
            at: .resolve(viewedSession: viewed, currentSession: secondInstance)
        ) == false
    )
}

@MainActor
@Test func liveActivityRestSurvivesAStoreReloadAtTheLiveEdge() throws {
    let container = try makeStoredWeek()
    defer { withExtendedLifetime(container) {} }
    let store = WorkoutStore(
        context: container.mainContext,
        defaults: .inMemory()
    )
    store.reload()

    let viewed = try #require(store.viewedSession)
    let loggedSet = try #require(viewed.exercises.first?.sets.first { $0.index == 0 })
    loggedSet.state = .logged
    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: viewed,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    store.reload()

    #expect(LiveActivityInvalidationPolicy.shouldEnd(content, at: store.liveEdge) == false)
}

@MainActor
private func storedWeekSession(dayNumber: Int, in context: ModelContext) throws -> Session? {
    let block = try context.fetch(FetchDescriptor<Block>()).first
    return block?.weeks.first { $0.number == 1 }?.sessions.first { $0.dayNumber == dayNumber }
}

@MainActor
private func makeStoredWeek() throws -> ModelContainer {
    let container = try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration("live-edge-\(UUID().uuidString)", isStoredInMemoryOnly: true)
    )
    let parsed = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            ParsedWeek(
                number: 1,
                days: (1...2).map { day in
                    ParsedSession(
                        dayNumber: day,
                        date: nil,
                        exercises: [
                            ParsedExercise(
                                name: "Squat",
                                coachNote: nil,
                                sets: (0...1).map { index in
                                    ParsedSet(
                                        index: index,
                                        prescribedReps: "5",
                                        prescribedLoad: "RPE8",
                                        percentOneRM: nil
                                    )
                                }
                            )
                        ]
                    )
                }
            )
        ]
    )
    container.mainContext.insert(BlockBuilder.makeBlock(from: parsed))
    try container.mainContext.save()
    return container
}
