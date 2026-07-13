import Testing

@testable import WorkoutTracker

@MainActor
@Test func restTriggerSuppressesWhenLoggedSetClearsCurrentWeek() throws {
    let loggedSet = makeCurrentWeekSet(states: [.logged], dayNumber: 1)
    let session = try #require(loggedSet.exercise?.session)

    let kind = RestTriggerPolicy.restKind(afterLogging: loggedSet, in: session)

    #expect(kind == nil)
}

@MainActor
@Test func restTriggerStartsWhenMakeupOpenExerciseRemainsInCurrentWeek() throws {
    let loggedSet = makeCurrentWeekSet(states: [.logged], dayNumber: 1)
    let makeupSet = makeCurrentWeekSet(states: [.pending], dayNumber: 2, exerciseName: "DB Row")
    let session = try #require(loggedSet.exercise?.session)
    connectCurrentWeek([session, try #require(makeupSet.exercise?.session)])

    let kind = RestTriggerPolicy.restKind(afterLogging: loggedSet, in: session, isSupersetMember: false)

    #expect(kind == .standard)
}

@MainActor
@Test func restTriggerStartsWhenOrdinaryPendingSetsRemain() throws {
    let loggedSet = makeCurrentWeekSet(states: [.logged, .pending], dayNumber: 1)
    let session = try #require(loggedSet.exercise?.session)

    let kind = RestTriggerPolicy.restKind(afterLogging: loggedSet, in: session, isSupersetMember: false)

    #expect(kind == .standard)
}

@MainActor
@Test func restTriggerMarksSupersetStartWhenLoggedSetBelongsToSuperset() throws {
    let loggedSet = makeCurrentWeekSet(states: [.logged, .pending], dayNumber: 1)
    let session = try #require(loggedSet.exercise?.session)

    let kind = RestTriggerPolicy.restKind(afterLogging: loggedSet, in: session, isSupersetMember: true)

    #expect(kind == .superset)
}

@MainActor
@Test func restTriggerKeepsRunningKindWhenNoNewRestButRestRunning() throws {
    let loggedSet = makeCurrentWeekSet(states: [.logged], dayNumber: 1)
    let session = try #require(loggedSet.exercise?.session)

    let standard = RestTriggerPolicy.restKind(
        afterLogging: loggedSet,
        in: session,
        isSupersetMember: false,
        isRestRunning: true
    )
    let superset = RestTriggerPolicy.restKind(
        afterLogging: loggedSet,
        in: session,
        isSupersetMember: true,
        isRestRunning: true
    )

    #expect(standard == .standard)
    #expect(superset == .superset)
}

@MainActor
private func makeCurrentWeekSet(
    states: [SetState],
    dayNumber: Int,
    exerciseName: String = "Bench Press"
) -> ExerciseSet {
    let session = Session(dayNumber: dayNumber, date: nil)
    let exercise = makeExercise(name: exerciseName, setStates: states)
    session.exercises = [exercise]
    connectCurrentWeek([session])
    return exercise.sets[0]
}

@MainActor
private func connectCurrentWeek(_ sessions: [Session]) {
    let week = Week(number: 1)
    week.sessions = sessions
}
