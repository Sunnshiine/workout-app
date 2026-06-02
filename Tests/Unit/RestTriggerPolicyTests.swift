import Testing

@testable import WorkoutTracker

@MainActor
@Test func restTriggerSuppressesWhenLoggedSetClearsCurrentWeek() throws {
    let loggedSet = makeCurrentWeekSet(states: [.logged], dayNumber: 1)
    let session = try #require(loggedSet.exercise?.session)

    let decision = RestTriggerPolicy.decision(afterLogging: loggedSet, in: session)

    #expect(decision == .none)
}

@MainActor
@Test func restTriggerStartsWhenMakeupOpenExerciseRemainsInCurrentWeek() throws {
    let loggedSet = makeCurrentWeekSet(states: [.logged], dayNumber: 1)
    let makeupSet = makeCurrentWeekSet(states: [.pending], dayNumber: 2, exerciseName: "DB Row")
    let session = try #require(loggedSet.exercise?.session)
    connectCurrentWeek([session, try #require(makeupSet.exercise?.session)])

    let decision = RestTriggerPolicy.decision(afterLogging: loggedSet, in: session)

    #expect(decision == .start)
}

@MainActor
@Test func restTriggerStartsWhenOrdinaryPendingSetsRemain() throws {
    let loggedSet = makeCurrentWeekSet(states: [.logged, .pending], dayNumber: 1)
    let session = try #require(loggedSet.exercise?.session)

    let decision = RestTriggerPolicy.decision(afterLogging: loggedSet, in: session)

    #expect(decision == .start)
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
