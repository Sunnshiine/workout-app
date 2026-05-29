import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func activeSetPresentationContainer() throws -> ModelContainer {
    try ModelContainer(
        for: LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "active-set-presentation-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@MainActor
@Test func setRowPresentationShowsLoggedSetWithAccentAndCheckmark() {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .logged)
    set.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: 8)

    let presentation = SetRowPresentation(set: set)

    #expect(presentation.title == "185x5@8")
    #expect(presentation.tone == .accent)
    #expect(presentation.showsCheckmark)
}

@MainActor
@Test func setRowPresentationShowsSkippedSetAsMutedSkip() {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .skipped)

    let presentation = SetRowPresentation(set: set)

    #expect(presentation.title == "skip")
    #expect(presentation.tone == .muted)
    #expect(!presentation.showsCheckmark)
}

@MainActor
@Test func setRowPresentationShowsPendingSetAsMutedPrescription() {
    let set = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)

    let presentation = SetRowPresentation(set: set)

    #expect(presentation.title == "5 · RPE 8")
    #expect(presentation.tone == .muted)
    #expect(!presentation.showsCheckmark)
}

@MainActor
@Test func loggedSetReviewPresentationDistinguishesStructuredAndUnstructuredLogs() {
    let structured = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .logged)
    structured.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: 8)
    let unstructured = ExerciseSet(index: 1, prescribedReps: "AMRAP", prescribedLoad: "BW", percentOneRM: nil, state: .logged)

    let structuredPresentation = LoggedSetReviewPresentation(set: structured)
    let unstructuredPresentation = LoggedSetReviewPresentation(set: unstructured)

    #expect(structuredPresentation.statusText == "Already logged")
    #expect(structuredPresentation.detailText == "185x5@8")
    #expect(structuredPresentation.allowsEditing)
    #expect(unstructuredPresentation.statusText == "Already logged")
    #expect(unstructuredPresentation.detailText == "Completed from sheet")
    #expect(!unstructuredPresentation.allowsEditing)
}

@MainActor
@Test func sessionProgressHeaderPresentationShowsCompactLocationAndRemainingCount() {
    let block = Block(tabName: "Block 27", squatTM: nil, benchTM: nil, deadliftTM: nil)
    let week = Week(number: 2)
    let session = Session(dayNumber: 3, date: nil)
    let exercise = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil)
    exercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .skipped),
        ExerciseSet(index: 2, prescribedReps: "5", prescribedLoad: "RPE 9", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [exercise]
    week.sessions = [session]
    block.weeks = [week]

    let presentation = SessionProgressHeaderPresentation(session: session)

    #expect(presentation.locationText == "W2 D3 ›")
    #expect(presentation.completedSetCount == 2)
    #expect(presentation.totalSetCount == 3)
    #expect(presentation.remainingText == "1 left")
    #expect(presentation.locationActionAccessibilityLabel == "Open Block Overview for Week 2, Day 3")
    #expect(presentation.progressAccessibilityValue == "W2 D3, 1 left")
}

@MainActor
@Test func sessionProgressHeaderPresentationBuildsOrderedRailSegments() {
    let session = Session(dayNumber: 1, date: nil)
    let firstExercise = Exercise(name: "Bench", baseName: "Bench", cadence: nil, coachNote: nil, order: 1)
    firstExercise.sets = [
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .skipped),
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
    ]
    let secondExercise = Exercise(name: "Row", baseName: "Row", cadence: nil, coachNote: nil, order: 2)
    secondExercise.sets = [
        ExerciseSet(index: 1, prescribedReps: "8", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [secondExercise, firstExercise]

    let presentation = SessionProgressHeaderPresentation(session: session)

    #expect(presentation.segments.map(\.state) == [.logged, .skipped, .currentPending, .futurePending])
}

@MainActor
@Test func sessionProgressHeaderPresentationUsesFocusedPendingSetForCurrentSegment() {
    let session = Session(dayNumber: 1, date: nil)
    let exercise = Exercise(name: "Bench", baseName: "Bench", cadence: nil, coachNote: nil, order: 0)
    exercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [exercise]

    let presentation = SessionProgressHeaderPresentation(
        session: session,
        activeSetID: ActiveSetID(exerciseOrder: 0, setIndex: 1)
    )

    #expect(presentation.segments.map(\.state) == [.futurePending, .currentPending])
}

@Test func overscrollToolbarVisibilityRevealsAfterPullingPastThreshold() {
    let visibility = OverscrollToolbarVisibility.hidden.updated(topContentOffset: 36)

    #expect(visibility == .visible)
}

@Test func overscrollToolbarVisibilityRemainsVisibleNearTop() {
    let visibility = OverscrollToolbarVisibility.visible.updated(topContentOffset: 0)

    #expect(visibility == .visible)
}

@Test func overscrollToolbarVisibilityDismissesAfterScrollingIntoContent() {
    let visibility = OverscrollToolbarVisibility.visible.updated(topContentOffset: -28)

    #expect(visibility == .hidden)
}

@MainActor
@Test func exerciseSummaryRowPresentationShowsBaseNameAndSetResults() {
    let exercise = Exercise(
        name: "2-3:1:0 Competition Squat",
        baseName: "Competition Squat",
        cadence: "2-3:1:0",
        coachNote: nil
    )
    let firstSet = ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .logged)
    firstSet.setLog = SetLog(weight: .pounds(185), reps: 8, rpe: 6)
    exercise.sets = [firstSet]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ Competition Squat · 185×8")
}

@MainActor
@Test func exerciseSummaryRowPresentationAbbreviatesConsecutiveSameWeightSets() {
    let exercise = Exercise(name: "BB RDL", baseName: "BB RDL", cadence: nil, coachNote: nil)
    let firstSet = ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .logged)
    firstSet.setLog = SetLog(weight: .pounds(225), reps: 8, rpe: 6)
    let secondSet = ExerciseSet(index: 1, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .logged)
    secondSet.setLog = SetLog(weight: .pounds(225), reps: 8, rpe: 6)
    let thirdSet = ExerciseSet(index: 2, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
    thirdSet.setLog = SetLog(weight: .pounds(245), reps: 6, rpe: 7)
    exercise.sets = [firstSet, secondSet, thirdSet]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ BB RDL · 225×8 / ×8 / 245×6")
}

@MainActor
@Test func exerciseSummaryRowPresentationShowsSkippedSetsAsSkip() {
    let exercise = Exercise(name: "BB RDL", baseName: "BB RDL", cadence: nil, coachNote: nil)
    let firstSet = ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .logged)
    firstSet.setLog = SetLog(weight: .pounds(225), reps: 8, rpe: 6)
    let secondSet = ExerciseSet(index: 1, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .logged)
    secondSet.setLog = SetLog(weight: .pounds(225), reps: 8, rpe: 6)
    let thirdSet = ExerciseSet(index: 2, prescribedReps: "8", prescribedLoad: "RPE 6", percentOneRM: nil, state: .skipped)
    exercise.sets = [firstSet, secondSet, thirdSet]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ BB RDL · 225×8 / ×8 / skip")
}

@MainActor
@Test func exerciseSummaryRowPresentationShowsRawLegacyLog() {
    let exercise = Exercise(
        name: "Standing Calve Raises",
        baseName: "Standing Calve Raises",
        cadence: nil,
        coachNote: nil,
        legacyLog: "25x12, 12"
    )
    exercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE 9", percentOneRM: nil, state: .logged),
        ExerciseSet(index: 1, prescribedReps: "12", prescribedLoad: "RPE 9", percentOneRM: nil, state: .logged)
    ]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ Standing Calve Raises · 25x12, 12")
}

@MainActor
@Test func exerciseSummaryRowPresentationPrefersStructuredLogsOverLegacyLog() {
    let exercise = Exercise(
        name: "Standing Calve Raises",
        baseName: "Standing Calve Raises",
        cadence: nil,
        coachNote: nil,
        legacyLog: "25x12, 12"
    )
    let set = ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE 9", percentOneRM: nil, state: .logged)
    set.setLog = SetLog(weight: .pounds(35), reps: 12, rpe: 9)
    exercise.sets = [set]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ Standing Calve Raises · 35×12")
}

@MainActor
@Test func exerciseSummaryRowPresentationShowsRawLegacyLogWhenSetLevelSkipExists() {
    let exercise = Exercise(
        name: "Standing Calve Raises",
        baseName: "Standing Calve Raises",
        cadence: nil,
        coachNote: nil,
        legacyLog: "25x12, 12"
    )
    exercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE 9", percentOneRM: nil, state: .logged),
        ExerciseSet(index: 1, prescribedReps: "12", prescribedLoad: "RPE 9", percentOneRM: nil, state: .skipped)
    ]

    let presentation = ExerciseSummaryRowPresentation(exercise: exercise)

    #expect(presentation.title == "✓ Standing Calve Raises · 25x12, 12")
}

@MainActor
@Test func lastPerformedCardPresentationShowsLabelSetLogAndSource() {
    let entry = LastPerformedEntry(
        fullName: "DB Fly",
        baseName: "DB Fly",
        result: SetLog(weight: .pounds(25), reps: 12, rpe: 9),
        performedOn: Date(timeIntervalSinceReferenceDate: 100),
        source: "W4 D3"
    )

    let presentation = LastPerformedCardPresentation(entry: entry)

    #expect(presentation.label == "Last Performed")
    #expect(presentation.resultText == "25x12@9")
    #expect(presentation.sourceText == "W4 D3")
}

@MainActor
@Test func lastPerformedCardPresentationShowsRawLegacyResultText() {
    let entry = LastPerformedEntry(
        fullName: "Standing Calve Raises",
        baseName: "Standing Calve Raises",
        resultText: "25x12, 12",
        performedOn: Date(timeIntervalSinceReferenceDate: 100),
        source: "W4 D3"
    )

    let presentation = LastPerformedCardPresentation(entry: entry)

    #expect(presentation.resultText == "25x12, 12")
    #expect(presentation.sourceText == "W4 D3")
}

@MainActor
@Test func lastPerformedCardPresentationUsesIndexLookupForExercise() throws {
    let container = try activeSetPresentationContainer()
    let context = container.mainContext
    context.insert(
        LastPerformedEntry(
            fullName: "2-3:1:0 BB RDL",
            baseName: "BB RDL",
            result: SetLog(weight: .pounds(185), reps: 7, rpe: 6),
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "W3 D1"
        )
    )
    try context.save()
    let exercise = Exercise(
        name: "2-3:1:0 BB RDL",
        baseName: "BB RDL",
        cadence: "2-3:1:0",
        coachNote: nil
    )

    let presentation = try #require(
        LastPerformedCardPresentation(exercise: exercise, index: LastPerformedIndex(context: context))
    )

    #expect(presentation.resultText == "185x7@6")
    #expect(presentation.sourceText == "W3 D1")
    withExtendedLifetime(container) {}
}

@MainActor
@Test func lastPerformedCardPresentationIsNilWhenIndexHasNoEntry() throws {
    let container = try activeSetPresentationContainer()
    let exercise = Exercise(
        name: "Bench Press",
        baseName: "Bench Press",
        cadence: nil,
        coachNote: nil
    )

    let presentation = LastPerformedCardPresentation(
        exercise: exercise,
        index: LastPerformedIndex(context: container.mainContext)
    )

    #expect(presentation == nil)
    withExtendedLifetime(container) {}
}
