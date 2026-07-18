import Testing

@testable import WorkoutTracker

/// A Session whose Exercises and Sets are deliberately inserted out of order so
/// the ordering owner has to sort them, not merely echo insertion order.
private func makeMultiExerciseSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)
    let bench = Exercise(name: "Bench Press", baseName: "Bench Press", cadence: nil, coachNote: nil, order: 1)
    bench.sets = [
        ExerciseSet(index: 1, prescribedReps: "6", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]
    let squat = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)
    squat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [bench, squat]
    return session
}

@MainActor
@Test func orderedSetsSortsByExerciseOrderThenSetIndex() {
    let session = makeMultiExerciseSession()

    let sequence = SessionSetOrder.orderedSets(in: session).map { $0.setID }

    #expect(
        sequence == [
            ActiveSetID(exerciseOrder: 0, setIndex: 0),
            ActiveSetID(exerciseOrder: 0, setIndex: 1),
            ActiveSetID(exerciseOrder: 1, setIndex: 0),
            ActiveSetID(exerciseOrder: 1, setIndex: 1)
        ]
    )
}

@MainActor
@Test func orderedSetsForEmptySessionIsEmpty() {
    let session = Session(dayNumber: 1, date: nil)

    #expect(SessionSetOrder.orderedSets(in: session).isEmpty)
    #expect(SessionSetOrder.firstPendingSet(in: session) == nil)
}

@MainActor
@Test func orderedSetsForSingleSetLine() {
    let session = Session(dayNumber: 1, date: nil)
    let exercise = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)
    let onlySet = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    exercise.sets = [onlySet]
    session.exercises = [exercise]

    let ordered = SessionSetOrder.orderedSets(in: session)

    #expect(ordered.count == 1)
    #expect(ordered.first?.set === onlySet)
    #expect(SessionSetOrder.firstPendingSet(in: session)?.set === onlySet)
}

@MainActor
@Test func firstPendingSetSkipsSettledSetsRegardlessOfState() {
    let session = makeMultiExerciseSession()
    let squat = session.exercises.first { $0.order == 0 }!
    let bench = session.exercises.first { $0.order == 1 }!
    // Squat: Logged then Skipped — both settled, both must be skipped over.
    squat.sets.first { $0.index == 0 }!.state = .logged
    squat.sets.first { $0.index == 1 }!.state = .skipped
    // Bench: first Pending Set is index 0.
    let expected = bench.sets.first { $0.index == 0 }!

    let first = SessionSetOrder.firstPendingSet(in: session)

    #expect(first?.set === expected)
    #expect(first?.setID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func firstPendingSetIsNilWhenNoSetIsPending() {
    let session = makeMultiExerciseSession()
    session.exercises.flatMap(\.sets).forEach { $0.state = .logged }

    #expect(SessionSetOrder.firstPendingSet(in: session) == nil)
}

@MainActor
@Test func nextPendingSetAdvancesInOrder() {
    let session = makeMultiExerciseSession()
    let squat = session.exercises.first { $0.order == 0 }!
    let firstSquatSet = squat.sets.first { $0.index == 0 }!

    let next = SessionSetOrder.nextPendingSet(after: firstSquatSet, in: session)

    #expect(next?.setID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
}

@MainActor
@Test func nextPendingSetSkipsSettledSetsAcrossExercises() {
    let session = makeMultiExerciseSession()
    let squat = session.exercises.first { $0.order == 0 }!
    let firstSquatSet = squat.sets.first { $0.index == 0 }!
    // Second Squat Set is settled, so the next Pending Set is the first Bench Set.
    squat.sets.first { $0.index == 1 }!.state = .logged

    let next = SessionSetOrder.nextPendingSet(after: firstSquatSet, in: session)

    #expect(next?.setID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func nextPendingSetWrapsToFirstPendingWhenGivenSetIsLastInOrder() {
    let session = makeMultiExerciseSession()
    let squat = session.exercises.first { $0.order == 0 }!
    let bench = session.exercises.first { $0.order == 1 }!
    let lastSet = bench.sets.first { $0.index == 1 }!
    // Settle the earlier Squat Sets so the wrap target is the first Bench Set.
    squat.sets.forEach { $0.state = .logged }

    let next = SessionSetOrder.nextPendingSet(after: lastSet, in: session)

    #expect(next?.setID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func nextPendingSetFromDetachedSetReturnsFirstPending() {
    let session = makeMultiExerciseSession()
    let squat = session.exercises.first { $0.order == 0 }!
    squat.sets.first { $0.index == 0 }!.state = .logged
    // A Set with no owning Exercise cannot be located in the order.
    let detached = ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)

    let next = SessionSetOrder.nextPendingSet(after: detached, in: session)

    #expect(next?.setID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
}

@MainActor
@Test func orderedSetsCoversEveryFixtureSetInStrictExerciseThenSetIndexOrder() {
    // The `openExercisesBlock` fixture, walked by the owner. Rather than re-run
    // the SUT's own flatMap-of-sorts as the oracle (a test that only fails if
    // both copies change together), assert the two independent properties that
    // "Exercise-order then Set-index order" actually means:
    //   • completeness — every fixture Set appears exactly once (order-insensitive), and
    //   • strict ordering — each position's (exerciseOrder, setIndex) is greater
    //     than the one before it.
    let scenario = WorkoutScenarios.openExercises()
    let session = scenario.currentSession!

    let sequence = SessionSetOrder.orderedSets(in: session).map { $0.setID }
    let everyFixtureSetID = Set(
        session.exercises.flatMap { exercise in
            exercise.sets.map { ActiveSetID(exerciseOrder: exercise.order, setIndex: $0.index) }
        }
    )

    #expect(!sequence.isEmpty)
    #expect(sequence.count == everyFixtureSetID.count)
    #expect(Set(sequence) == everyFixtureSetID)
    let isStrictlyAscending = zip(sequence, sequence.dropFirst()).allSatisfy { previous, next in
        (previous.exerciseOrder, previous.setIndex) < (next.exerciseOrder, next.setIndex)
    }
    #expect(isStrictlyAscending)
}
