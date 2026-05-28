import Testing

@testable import WorkoutTracker

@MainActor
@Test func moveOnCelebrationPresentationDescribesIncompleteClosedSession() {
    let session = makeMoveOnSession(
        weekNumber: 2,
        dayNumber: 3,
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .pending, .skipped]),
            makeMoveOnExercise(name: "Bench Press", order: 1, states: [.pending, .logged])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.weekText == "Week 2")
    #expect(presentation.titleText == "Day 3 Done")
    #expect(presentation.sublineText == "Moved on with 2 left")
}

@MainActor
@Test func moveOnCelebrationPresentationSelectsSuccessHapticForIncompleteSession() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .pending])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.hapticStyle == .success)
}

@MainActor
@Test func moveOnCelebrationPresentationShowsStatsInStableOrder() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .pending, .skipped]),
            makeMoveOnExercise(name: "Bench Press", order: 1, states: [.pending, .logged])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.stats.map(\.label) == ["Sets", "Exercises", "Left"])
    #expect(presentation.stats.map(\.value) == ["5", "2", "2"])
}

@MainActor
@Test func moveOnCelebrationPresentationDescribesPerfectSession() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .skipped, .logged])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.sublineText == "Perfect session")
    #expect(presentation.stats.map(\.label) == ["Sets", "Exercises", "Left"])
    #expect(presentation.stats.map(\.value) == ["3", "1", "0"])
}

@MainActor
@Test func moveOnCelebrationPresentationSelectsSuccessWithImpactHapticForPerfectSession() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .skipped])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.hapticStyle == .successWithImpact)
}

@MainActor
@Test func moveOnCelebrationPresentationProvidesAccessibilityTextForClosedSessionAndStats() {
    let session = makeMoveOnSession(
        weekNumber: 2,
        dayNumber: 3,
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .pending, .skipped]),
            makeMoveOnExercise(name: "Bench Press", order: 1, states: [.pending, .logged])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.accessibilityLabel == "Week 2, Day 3 Done")
    #expect(presentation.accessibilityValue == "5 Sets, 2 Exercises, 2 Left, Moved on with 2 left")
}

@MainActor
@Test func moveOnCelebrationPresentationUsesApprovedQuoteRotation() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(
        presentation.quotes == [
            "You're fucking amazing.",
            "God damn!",
            "Get it girl!",
            "Shake it!"
        ]
    )
}

@MainActor
private func makeMoveOnSession(
    weekNumber: Int = 1,
    dayNumber: Int = 1,
    exercises: [Exercise]
) -> Session {
    let week = Week(number: weekNumber)
    let session = Session(dayNumber: dayNumber, date: nil)
    session.exercises = exercises
    week.sessions = [session]
    return session
}

@MainActor
private func makeMoveOnExercise(name: String, order: Int, states: [SetState]) -> Exercise {
    let exercise = Exercise(name: name, baseName: name, cadence: nil, coachNote: nil, order: order)
    exercise.sets = states.enumerated().map { index, state in
        ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: state)
    }
    return exercise
}
