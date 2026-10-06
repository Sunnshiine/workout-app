import Testing

@testable import WorkoutTracker

private func makeSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)
    let squat = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)
    squat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    ]
    let bench = Exercise(name: "Bench Press", baseName: "Bench Press", cadence: nil, coachNote: nil, order: 1)
    bench.sets = [
        ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [bench, squat]
    return session
}

private func makePendingSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)
    let squat = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)
    squat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [squat]
    return session
}

private func makeMultiExercisePendingSession() -> Session {
    let session = makePendingSession()
    let bench = Exercise(name: "Bench Press", baseName: "Bench Press", cadence: nil, coachNote: nil, order: 1)
    bench.sets = [
        ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]
    session.exercises.append(bench)
    return session
}

private func makePlannedSupersetSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)
    let row = Exercise(name: "DB Row", baseName: "DB Row", cadence: nil, coachNote: nil, order: 0)
    row.sets = [
        ExerciseSet(index: 0, prescribedReps: "10", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]
    let squat = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 1)
    squat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    ]
    let bench = Exercise(name: "Bench Press", baseName: "Bench Press", cadence: nil, coachNote: nil, order: 2)
    bench.sets = [
        ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [row, squat, bench]
    return session
}

@MainActor
@Test func advanceAfterLogSkipsSettledSetsToNextPendingSetAcrossExercises() throws {
    // Logging the first Squat Set, with the second Squat Set already Skipped,
    // advances past both settled Sets to the first Pending Set of the next
    // Exercise — a Logged/Skipped/Pending mix that would trip a walk spelling
    // the Pending predicate inconsistently.
    let session = makeMultiExercisePendingSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let secondSquatSet = try #require(squat.sets.first { $0.index == 1 })
    firstSquatSet.state = .logged
    secondSquatSet.state = .skipped
    let focus = ActiveSetFocusManager(session: session)

    focus.advanceAfterLog(firstSquatSet, in: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func initialActiveSetIsFirstPendingSetInSessionOrder() {
    let session = makeSession()
    let focus = ActiveSetFocusManager(session: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
}

@MainActor
@Test func loggingActiveSetAdvancesToNextPendingSetInSameExercise() throws {
    let session = makePendingSession()
    let set = try #require(session.exercises.first?.sets.first { $0.index == 0 })
    let focus = ActiveSetFocusManager(session: session)

    set.state = .logged
    focus.advanceAfterLog(set, in: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
}

@MainActor
@Test func loggingActiveSetAdvancesToFirstPendingSetInNextExercise() throws {
    let session = makeMultiExercisePendingSession()
    let squatSets = try #require(session.exercises.first { $0.order == 0 }?.sets)
    squatSets.forEach { $0.state = .logged }
    let finalSquatSet = try #require(squatSets.first { $0.index == 1 })
    let focus = ActiveSetFocusManager(session: session)

    focus.advanceAfterLog(finalSquatSet, in: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func focusingACompletedExercisesLoggedSetPreservesCurrentFocusAndTogglesItsReview() throws {
    let session = makeMultiExercisePendingSession()
    let squatSets = try #require(session.exercises.first { $0.order == 0 }?.sets)
    squatSets.forEach { $0.state = .logged }
    let firstSquatSet = try #require(squatSets.first { $0.index == 0 })
    let finalSquatSet = try #require(squatSets.first { $0.index == 1 })
    let focus = ActiveSetFocusManager(session: session)

    focus.advanceAfterLog(finalSquatSet, in: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))

    focus.focus(on: firstSquatSet)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(focus.expandedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))

    focus.focus(on: firstSquatSet)

    #expect(focus.expandedLoggedSetID == nil)
}

@MainActor
@Test func loggedSetReviewOwnsVisualFocusWhileRememberingActivePendingSet() throws {
    let session = makeSession()
    let loggedSet = try #require(session.exercises.first { $0.order == 0 }?.sets.first { $0.index == 0 })
    let focus = ActiveSetFocusManager(session: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
    #expect(focus.visualFocusOwner == .activeSet(ActiveSetID(exerciseOrder: 0, setIndex: 1)))

    focus.focus(on: loggedSet)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
    #expect(focus.expandedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(focus.visualFocusOwner == .loggedSetReview(ActiveSetID(exerciseOrder: 0, setIndex: 0)))

    focus.collapseLoggedSetReview()

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
    #expect(focus.expandedLoggedSetID == nil)
    #expect(focus.visualFocusOwner == .activeSet(ActiveSetID(exerciseOrder: 0, setIndex: 1)))
}

@MainActor
@Test func unstructuredLoggedSetReviewOwnsVisualFocusWhileRememberingActivePendingSet() throws {
    let session = makeSession()
    let loggedSet = try #require(session.exercises.first { $0.order == 0 }?.sets.first { $0.index == 0 })
    loggedSet.setLog = nil
    let focus = ActiveSetFocusManager(session: session)

    focus.focus(on: loggedSet)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
    #expect(focus.visualFocusOwner == .loggedSetReview(ActiveSetID(exerciseOrder: 0, setIndex: 0)))
}

@MainActor
@Test func skippingActiveSetAdvancesToNextPendingSet() throws {
    let session = makePendingSession()
    let set = try #require(session.exercises.first?.sets.first { $0.index == 0 })
    let focus = ActiveSetFocusManager(session: session)

    set.state = .skipped
    focus.advanceAfterSkip(set, in: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
}

@MainActor
@Test func skippingFinalPendingSetAdvancesToFirstPendingSetInNextExercise() throws {
    let session = makeMultiExercisePendingSession()
    let squatSets = try #require(session.exercises.first { $0.order == 0 }?.sets)
    squatSets.forEach { $0.state = .skipped }
    let finalSquatSet = try #require(squatSets.first { $0.index == 1 })
    let focus = ActiveSetFocusManager(session: session)

    focus.advanceAfterSkip(finalSquatSet, in: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func swappingFocusMakesTappedSetActive() throws {
    let session = makePendingSession()
    let set = try #require(session.exercises.first?.sets.first { $0.index == 1 })
    let focus = ActiveSetFocusManager(session: session)

    focus.focus(on: set)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
}

@MainActor
@Test func completingSessionClearsActiveSet() throws {
    let session = makePendingSession()
    let sets = try #require(session.exercises.first?.sets)
    sets.forEach { $0.state = .logged }
    let finalSet = try #require(sets.first { $0.index == 1 })
    let focus = ActiveSetFocusManager(session: session)

    focus.advanceAfterLog(finalSet, in: session)

    #expect(focus.activeSetID == nil)
}

@MainActor
@Test func creatingSupersetAroundCurrentActiveSetKeepsThatSetActiveAndFirst() throws {
    let session = makeMultiExercisePendingSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let focus = ActiveSetFocusManager(session: session)

    #expect(focus.createSuperset(with: [bench, squat], in: session))

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))

    firstSquatSet.state = .logged
    focus.advanceAfterLog(firstSquatSet, in: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func creatingPlannedSupersetFromOutOfFocusExercisesDoesNotChangeCurrentActiveSet() throws {
    let session = makePlannedSupersetSession()
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let focus = ActiveSetFocusManager(session: session)

    #expect(focus.createSuperset(with: [squat, bench], in: session))

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
}

@MainActor
@Test func plannedSupersetActivatesWhenNormalProgressionReachesEitherPairedExercise() throws {
    let session = makePlannedSupersetSession()
    let row = try #require(session.exercises.first { $0.order == 0 })
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let rowSet = try #require(row.sets.first { $0.index == 0 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let focus = ActiveSetFocusManager(session: session)
    focus.createSuperset(with: [squat, bench], in: session)

    rowSet.state = .logged
    focus.advanceAfterLog(rowSet, in: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))

    firstSquatSet.state = .logged
    focus.advanceAfterLog(firstSquatSet, in: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
}

@MainActor
@Test func aSupersetSnapshotsBothSidesAndFocusesThePairedExercisesNextPendingSet() throws {
    let session = makeMultiExercisePendingSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let focus = ActiveSetFocusManager(session: session)

    #expect(focus.createSuperset(with: [squat, bench], in: session))

    let initial = focus.snapshot(in: session)
    #expect(initial.supersets.map { $0.exercises.map(\.order) } == [[0, 1]])
    #expect(initial.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))

    #expect(focus.focusNextSupersetSet(for: bench, in: session))

    #expect(focus.snapshot(in: session).activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func pairingEligibilityRejectsCompletedAndAlreadyPairedExercises() throws {
    let session = makePlannedSupersetSession()
    let row = try #require(session.exercises.first { $0.order == 0 })
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let focus = ActiveSetFocusManager(session: session)

    #expect(focus.canPair(row, in: session))
    #expect(focus.canPair(squat, in: session))
    #expect(focus.canPair(bench, in: session))

    #expect(focus.createSuperset(from: squat, to: bench, in: session))

    #expect(!focus.canPair(squat, in: session))
    #expect(!focus.canPair(bench, in: session))

    focus.dismissSuperset(containing: squat, in: session)
    bench.sets.forEach { $0.state = .logged }

    #expect(focus.canPair(row, in: session))
    #expect(focus.canPair(squat, in: session))
    #expect(!focus.canPair(bench, in: session))
}

@MainActor
@Test func creatingAPlannedSupersetSnapshotsItWithoutChangingFocus() throws {
    let session = makePlannedSupersetSession()
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let focus = ActiveSetFocusManager(session: session)

    #expect(focus.createSuperset(from: squat, to: bench, in: session))

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))

    let snapshot = focus.snapshot(in: session)
    #expect(snapshot.supersets.map { $0.exercises.map(\.order) } == [[1, 2]])
    #expect(snapshot.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(snapshot.pairableExerciseOrders.isEmpty)
}

@MainActor
@Test func manualSupersetDismissRemovesItWithoutChangingSetLogs() throws {
    let session = makeMultiExercisePendingSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let log = SetLog(weight: .pounds(185), reps: 5, rpe: .seven)
    firstSquatSet.setLog = log
    firstSquatSet.state = .logged
    let focus = ActiveSetFocusManager(session: session)

    #expect(focus.createSuperset(from: squat, to: bench, in: session))
    focus.dismissSuperset(containing: squat, in: session)

    #expect(focus.snapshot(in: session).supersets.isEmpty)
    #expect(firstSquatSet.setLog == log)
    #expect(firstSquatSet.state == .logged)
}

@MainActor
@Test func supersetStateDoesNotPersistAcrossNewFocusManagerInstance() throws {
    let session = makeMultiExercisePendingSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let focus = ActiveSetFocusManager(session: session)
    #expect(focus.createSuperset(from: squat, to: bench, in: session))

    let relaunchedFocus = ActiveSetFocusManager(session: session)

    #expect(relaunchedFocus.snapshot(in: session).supersets.isEmpty)
}

@MainActor
@Test func aSupersetLeavesTheSnapshotOnceEitherExerciseHasNoPendingSet() throws {
    let session = makeMultiExercisePendingSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let focus = ActiveSetFocusManager(session: session)
    #expect(focus.createSuperset(from: squat, to: bench, in: session))

    squat.sets.forEach { $0.state = .skipped }

    #expect(focus.snapshot(in: session).supersets.isEmpty)
}

@MainActor
@Test func focusingASetNotifiesAReaderOfTheStageFocus() throws {
    let session = makePendingSession()
    let secondSet = try #require(session.exercises.first?.sets.first { $0.index == 1 })
    let coordinator = SessionCoordinator(session: session)
    let changes = ObservedChanges()
    changes.watch { _ = coordinator.stage(in: session, lookup: .empty) }

    coordinator.focus(on: secondSet)

    #expect(changes.fired == 1)
    #expect(coordinator.visualFocusOwner == .activeSet(ActiveSetID(exerciseOrder: 0, setIndex: 1)))
}

@MainActor
@Test func creatingASupersetNotifiesAReaderOfTheStageInputs() throws {
    let session = makePlannedSupersetSession()
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let coordinator = SessionCoordinator(session: session)
    let changes = ObservedChanges()
    changes.watch { _ = coordinator.stage(in: session, lookup: .empty) }

    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))

    #expect(changes.fired == 1)
    #expect(coordinator.stage(in: session, lookup: .empty).queue.rows.map(\.id) == ["exercise-0", "superset-1"])
}
