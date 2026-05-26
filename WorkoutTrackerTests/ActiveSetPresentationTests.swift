import Testing

@testable import WorkoutTracker

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
@Test func sessionProgressHeaderPresentationShowsBreadcrumbProgressAndRemainingCount() {
    let block = Block(tabName: "Block 27", squatTM: nil, benchTM: nil, deadliftTM: nil)
    let week = Week(number: 2)
    let session = Session(dayNumber: 3, date: nil)
    let exercise = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil)
    exercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .skipped),
        ExerciseSet(index: 2, prescribedReps: "5", prescribedLoad: "RPE 9", percentOneRM: nil, state: .pending),
    ]
    session.exercises = [exercise]
    week.sessions = [session]
    block.weeks = [week]

    let presentation = SessionProgressHeaderPresentation(session: session)

    #expect(presentation.breadcrumb == "Block 27 · W2 D3")
    #expect(presentation.completedSetCount == 2)
    #expect(presentation.totalSetCount == 3)
    #expect(presentation.remainingText == "1 left")
    #expect(abs(presentation.progress - 2.0 / 3.0) < 0.001)
}
