import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func liveActivityCreationPolicyAllowsOnlySuccessfulUserSetLogInCurrentSession() {
    let allowedEvent = LiveActivityProductionEvent(
        source: .userSetLog,
        outcome: .success,
        sessionScope: .currentSession
    )

    #expect(LiveActivityCreationPolicy.shouldCreateOrUpdate(for: allowedEvent))

    let refusedEvents =
        LiveActivityProductionEvent.Source.allCases
        .filter { $0 != .userSetLog }
        .map {
            LiveActivityProductionEvent(source: $0, outcome: .success, sessionScope: .currentSession)
        }
        + [
            LiveActivityProductionEvent(source: .userSetLog, outcome: .failure, sessionScope: .currentSession),
            LiveActivityProductionEvent(source: .userSetLog, outcome: .success, sessionScope: .nonCurrentSession)
        ]

    for event in refusedEvents {
        #expect(!LiveActivityCreationPolicy.shouldCreateOrUpdate(for: event))
    }
}

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
    #expect(content.variant == .restTimerSetsLeft)
    #expect(content.restStartDate == startDate)
    #expect(content.restEndDate == endDate)
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
@Test func liveActivityContentFallsBackToOpenExerciseInCurrentWeek() throws {
    let openExercise = makeExercise(name: "DB Row", order: 0, setStates: [.pending])
    let openSession = makeSingleSession(dayNumber: 1, exercises: [openExercise])
    let currentExercise = makeExercise(name: "Bench Press", order: 0, setStates: [.logged])
    let currentSession = makeSingleSession(dayNumber: 3, exercises: [currentExercise])
    connectCurrentWeek([openSession, currentSession])
    let loggedSet = try #require(currentExercise.sets.first)

    let content = try #require(
        LiveActivityRestContentBuilder.content(
            afterLogging: loggedSet,
            in: currentSession,
            restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
            restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
        )
    )

    #expect(content.exerciseName == "DB Row")
    #expect(content.setsLeftText == "1 set left")
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
private func makeSingleSession(dayNumber: Int = 1, exercises: [Exercise]) -> Session {
    let session = Session(dayNumber: dayNumber, date: nil)
    session.exercises = exercises
    connectCurrentWeek([session])
    return session
}

@MainActor
private func connectCurrentWeek(_ sessions: [Session]) {
    let week = Week(number: 1)
    week.sessions = sessions
}
