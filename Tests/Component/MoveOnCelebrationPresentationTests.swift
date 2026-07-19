import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func moveOnCelebrationPresentationDescribesClosedSession() {
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
@Test func moveOnCelebrationPresentationDescribesTheStaticShell() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .pending])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session, quoteText: "Steady work travels.")

    #expect(presentation.actionText == "Move On")
    #expect(presentation.setsCopyText == "Logged Sets are saved. Open Sets stay with the Week.")
    #expect(presentation.tapHintText == "Tap anywhere to continue")
    #expect(presentation.quoteText == "Steady work travels.")
}

// Completion, Not Achievement (DESIGN.md §5.7): the ceremony is identical on an
// ordinary day with Skipped Sets and on a perfect Session. There is no richer
// variant — one swell-and-peak Move On haptic marks the athlete's choice.
@MainActor
@Test func moveOnCelebrationPresentationPlaysOneMoveOnHapticForAnIncompleteSession() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .pending, .skipped])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.haptic == .moveOn)
}

@MainActor
@Test func moveOnCelebrationPresentationPlaysTheSameMoveOnHapticForAPerfectSession() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .logged])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.haptic == .moveOn)
}

@MainActor
@Test func moveOnCelebrationHapticIsIdenticalRegardlessOfSkippedSets() {
    let perfect = MoveOnCelebrationPresentation(
        session: makeMoveOnSession(
            exercises: [makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .logged])]
        )
    )
    let withSkips = MoveOnCelebrationPresentation(
        session: makeMoveOnSession(
            exercises: [makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .skipped, .pending])]
        )
    )

    #expect(perfect.haptic == withSkips.haptic)
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
@Test func moveOnCelebrationPresentationDescribesPerfectSessionStats() {
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

// No elapsed-time UI survives the redesign (DESIGN.md §5.7): the accessibility
// value reads the action, the ceremony title, the sets copy, then the stats —
// never an elapsed-time or time-range phrase.
@MainActor
@Test func moveOnCelebrationPresentationComposesAccessibilityWithoutElapsedTime() {
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
    #expect(
        presentation.accessibilityValue
            == "Move On, Steady work travels., Logged Sets are saved. Open Sets stay with the Week., 5 Sets, 2 Exercises, 2 Left"
    )
    #expect(presentation.accessibilityHint == presentation.tapHintText)
    #expect(!presentation.accessibilityValue.contains("elapsed"))
    #expect(!presentation.accessibilityValue.contains(" to "))
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
    #expect(presentation.accessibilityValue.contains(MoveOnCelebrationPresentation.longQuoteFixture))
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
