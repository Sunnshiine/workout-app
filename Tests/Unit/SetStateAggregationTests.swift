import Testing

@testable import WorkoutTracker

// Set State aggregation vocabulary (PRD #329): the atoms on ExerciseSet and the
// completeness / pending / count aggregates on Exercise and Session. See
// CONTEXT.md — an Exercise is complete when all prescribed Sets are Logged or
// Skipped; the empty-set case is deliberately NOT complete.

@MainActor
private func makeExercise(_ states: [SetState], order: Int = 0) -> Exercise {
    let exercise = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: order)
    exercise.sets = states.enumerated().map { index, state in
        ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: state)
    }
    return exercise
}

@MainActor
private func makeSession(_ exercises: [Exercise]) -> Session {
    let session = Session(dayNumber: 1, date: nil)
    session.exercises = exercises
    return session
}

// MARK: - ExerciseSet atoms

@MainActor
@Test func exerciseSetPendingAtom() {
    #expect(ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "", percentOneRM: nil, state: .pending).isPending)
    #expect(!ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "", percentOneRM: nil, state: .logged).isPending)
    #expect(!ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "", percentOneRM: nil, state: .skipped).isPending)
}

@MainActor
@Test func exerciseSetSettledAtom() {
    #expect(!ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "", percentOneRM: nil, state: .pending).isSettled)
    #expect(ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "", percentOneRM: nil, state: .logged).isSettled)
    #expect(ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "", percentOneRM: nil, state: .skipped).isSettled)
}

// MARK: - Exercise aggregates

@MainActor
@Test func exerciseIsCompleteWhenAllSetsSettled() {
    #expect(makeExercise([.logged, .skipped]).isComplete)
    #expect(makeExercise([.logged, .logged]).isComplete)
    #expect(!makeExercise([.logged, .pending]).isComplete)
    #expect(!makeExercise([.pending]).isComplete)
}

@MainActor
@Test func exerciseWithZeroSetsIsNotComplete() {
    #expect(!makeExercise([]).isComplete)
}

@MainActor
@Test func exerciseHasPendingSet() {
    #expect(makeExercise([.logged, .pending]).hasPendingSet)
    #expect(makeExercise([.pending]).hasPendingSet)
    #expect(!makeExercise([.logged, .skipped]).hasPendingSet)
    #expect(!makeExercise([]).hasPendingSet)
}

@MainActor
@Test func exerciseCompletedSetCount() {
    #expect(makeExercise([.logged, .skipped, .pending]).completedSetCount == 2)
    #expect(makeExercise([.pending, .pending]).completedSetCount == 0)
    #expect(makeExercise([]).completedSetCount == 0)
}

@MainActor
@Test func exercisePendingSetCount() {
    #expect(makeExercise([.logged, .skipped, .pending]).pendingSetCount == 1)
    #expect(makeExercise([.pending, .pending]).pendingSetCount == 2)
    #expect(makeExercise([.logged, .skipped]).pendingSetCount == 0)
    #expect(makeExercise([]).pendingSetCount == 0)
}

// MARK: - Session aggregates

@MainActor
@Test func sessionIsCompleteWhenAllSetsSettled() {
    #expect(makeSession([makeExercise([.logged, .skipped]), makeExercise([.logged])]).isComplete)
    #expect(!makeSession([makeExercise([.logged]), makeExercise([.pending])]).isComplete)
}

@MainActor
@Test func sessionWithZeroSetsIsNotComplete() {
    #expect(!makeSession([]).isComplete)
    #expect(!makeSession([makeExercise([])]).isComplete)
}

@MainActor
@Test func sessionCompletenessIsDecidedOverTheFlattenedSetCollection() {
    // Degenerate per the glossary (an Exercise has ≥1 Set), but pins the single
    // empty-set boundary the model and the Stage now share: completeness is a
    // property of the flattened Set collection, so a stray zero-Set Exercise
    // alongside fully settled work neither blocks nor fakes completion.
    #expect(makeSession([makeExercise([.logged, .skipped]), makeExercise([])]).isComplete)
    #expect(!makeSession([makeExercise([.logged]), makeExercise([.pending])]).isComplete)
}

@MainActor
@Test func sessionCompletedAndTotalSetCounts() {
    let session = makeSession([makeExercise([.logged, .skipped, .pending]), makeExercise([.logged, .pending])])
    #expect(session.completedSetCount == 3)
    #expect(session.totalSetCount == 5)

    let empty = makeSession([])
    #expect(empty.completedSetCount == 0)
    #expect(empty.totalSetCount == 0)
}

@MainActor
@Test func sessionPendingSetCount() {
    let session = makeSession([makeExercise([.logged, .skipped, .pending]), makeExercise([.logged, .pending])])
    #expect(session.pendingSetCount == 2)

    #expect(makeSession([makeExercise([.logged, .skipped])]).pendingSetCount == 0)
    #expect(makeSession([]).pendingSetCount == 0)
}
