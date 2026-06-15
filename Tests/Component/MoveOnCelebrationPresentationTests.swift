import Foundation
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
@Test func moveOnCelebrationPresentationDescribesF3StaticShell() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .pending])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(session: session, quoteText: "Steady work travels.")

    #expect(presentation.markText == "TFN")
    #expect(presentation.actionText == "Move On")
    #expect(presentation.setsCopyText == "Logged Sets are saved. Open Sets stay with the Week.")
    #expect(presentation.tapHintText == "Tap anywhere to continue")
    #expect(presentation.quoteText == "Steady work travels.")
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
@Test func moveOnCelebrationPresentationShowsElapsedTimeWhenTimingIsAvailable() {
    let firstLoggedAt = makeDate(hour: 18, minute: 14)
    let requestedAt = makeDate(hour: 19, minute: 6)
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, loggedAt: firstLoggedAt),
            makeMoveOnExercise(name: "Bench Press", order: 1, loggedAt: makeDate(hour: 18, minute: 42))
        ]
    )

    let presentation = MoveOnCelebrationPresentation(
        session: session,
        requestedAt: requestedAt
    )

    #expect(presentation.timing == .available(elapsedText: "52 min elapsed", timeRangeText: "6:14 PM → 7:06 PM"))
    #expect(presentation.stats.map(\.label) == ["Sets", "Exercises", "Left"])
}

@MainActor
@Test func moveOnCelebrationPresentationFallsBackWhenTimingIsUnavailable() {
    let session = makeMoveOnSession(
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged])
        ]
    )

    let presentation = MoveOnCelebrationPresentation(
        session: session,
        requestedAt: Date(timeIntervalSinceReferenceDate: 1_185)
    )

    #expect(presentation.timing == .unavailable)
    #expect(presentation.stats.first { $0.label == "Time" } == nil)
}

@MainActor
@Test func moveOnCelebrationPresentationFallsBackWhenAnyLoggedSetIsMissingTimingEvidence() {
    let exercise = makeMoveOnExercise(name: "Back Squat", order: 0, states: [.logged, .logged])
    exercise.sets[1].loggedAt = Date(timeIntervalSinceReferenceDate: 1_120)
    let session = makeMoveOnSession(exercises: [exercise])

    let presentation = MoveOnCelebrationPresentation(
        session: session,
        requestedAt: Date(timeIntervalSinceReferenceDate: 1_185)
    )

    #expect(presentation.timing == .unavailable)
    #expect(presentation.stats.first { $0.label == "Time" } == nil)
}

@MainActor
@Test func moveOnCelebrationPresentationComposesAccessibilityTimingOnlyWhenAvailable() {
    let session = makeMoveOnSession(
        weekNumber: 2,
        dayNumber: 3,
        exercises: [
            makeMoveOnExercise(name: "Back Squat", order: 0, loggedAt: makeDate(hour: 18, minute: 14))
        ]
    )

    let presentation = MoveOnCelebrationPresentation(
        session: session,
        requestedAt: makeDate(hour: 19, minute: 6),
        quoteText: "Steady work travels."
    )
    let expectedAccessibilityValue = [
        "Move On",
        "Steady work travels.",
        "Logged Sets are saved. Open Sets stay with the Week.",
        "52 min elapsed",
        "6:14 PM to 7:06 PM",
        "1 Sets",
        "1 Exercises",
        "0 Left"
    ].joined(separator: ", ")

    #expect(presentation.accessibilityValue == expectedAccessibilityValue)

    let unavailablePresentation = MoveOnCelebrationPresentation(
        session: makeMoveOnSession(
            exercises: [
                makeMoveOnExercise(name: "Bench Press", order: 0, states: [.logged])
            ]
        ),
        requestedAt: makeDate(hour: 19, minute: 6),
        quoteText: "Steady work travels."
    )

    #expect(!unavailablePresentation.accessibilityValue.contains("elapsed"))
    #expect(!unavailablePresentation.accessibilityValue.contains(" to "))
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
            == "Move On, Steady work travels., Logged Sets are saved. Open Sets stay with the Week., 5 Sets, 2 Exercises, 2 Left"
    )
    #expect(presentation.accessibilityHint == presentation.tapHintText)
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

@MainActor
private func makeMoveOnExercise(name: String, order: Int, loggedAt: Date) -> Exercise {
    let exercise = makeMoveOnExercise(name: name, order: order, states: [.logged])
    exercise.sets[0].loggedAt = loggedAt
    return exercise
}

private func makeDate(hour: Int, minute: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone.current
    components.year = 2026
    components.month = 6
    components.day = 6
    components.hour = hour
    components.minute = minute
    return components.date ?? Date(timeIntervalSinceReferenceDate: 0)
}
