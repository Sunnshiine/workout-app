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
    #expect(presentation.titleText == "Day 3, done.")
}

@MainActor
@Test func moveOnCelebrationPresentationPrefixesContextWithBlockTab() {
    let session = makeMoveOnSession(
        blockTab: "Block 27",
        weekNumber: 2,
        dayNumber: 2,
        exercises: [
            makeMoveOnExercise(name: "Bench Press", order: 0, states: [.logged, .logged])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.contextText == "Block 27 · Week 2 · Day 2")
    #expect(presentation.titleText == "Day 2, done.")
}

@MainActor
@Test func moveOnCelebrationPresentationDescribesStaticShell() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .pending])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session, quoteText: "Steady work travels.")

    #expect(presentation.actionText == "Move On")
    #expect(presentation.continueText == "Continue")
    #expect(presentation.quoteText == "Steady work travels.")
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
@Test func moveOnCelebrationPresentationDescribesPerfectSessionWithoutRicherVariant() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .skipped, .logged])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session)

    #expect(presentation.stats.map(\.label) == ["Sets", "Exercises", "Left"])
    #expect(presentation.stats.map(\.value) == ["3", "1", "0"])
    // Completion, not achievement: there is no elapsed-time surface on the ceremony.
    #expect(!presentation.accessibilityValue.contains("elapsed"))
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
    #expect(
        presentation.accessibilityValue
            == "Day 3, done., Steady work travels., 5 Sets, 2 Exercises, 2 Left"
    )
    #expect(presentation.accessibilityHint == "Double tap to continue")
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
    blockTab: String? = nil,
    weekNumber: Int = 1,
    dayNumber: Int = 1,
    exercises: [Exercise]
) -> Session {
    let week = Week(number: weekNumber)
    if let blockTab {
        let block = Block(tabName: blockTab, squatTM: nil, benchTM: nil, deadliftTM: nil)
        week.block = block
        block.weeks = [week]
    }
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
