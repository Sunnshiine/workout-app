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

    #expect(presentation.contextText == "Week 2 · Day 3")
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

    #expect(presentation.stats.map(\.label) == ["Sets", "Exercises", "Left"])
    #expect(presentation.stats.map(\.value) == ["3", "1", "0"])
}

@MainActor
@Test func moveOnCelebrationPresentationCarriesPendingSetCountInLeftStat() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.pending, .skipped, .pending]),
            makeMoveOnExercise(name: "Bench Press", order: 1, states: [.logged, .pending])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.stats.first { $0.label == "Left" }?.value == "3")
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
@Test func moveOnCelebrationPresentationSelectsAnimatedBloomForPerfectSession() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .skipped])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.visualTreatment(reduceMotion: false) == .animatedBloom)
}

@MainActor
@Test func moveOnCelebrationPresentationKeepsStaticLensForReducedMotionPerfectSession() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .skipped])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.visualTreatment(reduceMotion: true) == .reducedMotionLens)
}

@MainActor
@Test func moveOnCelebrationPresentationSelectsAnimatedBloomForIncompleteSession() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .pending])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.visualTreatment(reduceMotion: false) == .animatedBloom)
    #expect(presentation.visualTreatment(reduceMotion: true) == .reducedMotionLens)
}

@MainActor
@Test func moveOnCelebrationPresentationLoopsBloomForSeveralSecondsUnlessMotionIsReduced() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .pending])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)
    let motion = presentation.bloomMotion(reduceMotion: false)

    #expect(motion?.loopDuration == 7.2)
    #expect(motion?.pulseDuration == 1.2)
    #expect(motion?.repeatCount == 6)
    #expect(presentation.bloomMotion(reduceMotion: true) == nil)
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

    let presentation = MoveOnCelebrationPresentation(session: session, quoteText: "Steady work travels.")

    #expect(presentation.accessibilityLabel == "Week 2, Day 3")
    #expect(presentation.accessibilityValue == "Steady work travels., 5 Sets, 2 Exercises, 2 Left")
    #expect(presentation.accessibilityHint == "Tap anywhere to continue")
}

@MainActor
@Test func moveOnCelebrationPresentationSelectsOneStableApprovedQuote() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)
    let selectedQuote = presentation.quoteText

    #expect(MoveOnCelebrationPresentation.approvedQuotes.contains(selectedQuote))
    #expect(presentation.quoteText == selectedQuote)
}

@MainActor
@Test func moveOnCelebrationLongQuoteFixtureExercisesWrappingState() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.pending, .pending, .logged])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(
        session: session,
        quoteText: MoveOnCelebrationPresentation.longQuoteFixture
    )

    #expect(MoveOnCelebrationPresentation.longQuoteFixture.count >= 110)
    #expect(!MoveOnCelebrationPresentation.approvedQuotes.contains(presentation.quoteText))
    #expect(presentation.accessibilityValue.hasPrefix(MoveOnCelebrationPresentation.longQuoteFixture))
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
