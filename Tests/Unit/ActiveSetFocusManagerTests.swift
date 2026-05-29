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
@Test func loggingActiveSetRecordsMomentumFlowTransition() throws {
    let session = makePendingSession()
    let set = try #require(session.exercises.first?.sets.first { $0.index == 0 })
    let focus = ActiveSetFocusManager(session: session)

    set.state = .logged
    focus.advanceAfterLog(set, in: session)

    #expect(
        focus.activeSetTransition
            == ActiveSetTransition(
                kind: .momentumFlow,
                outgoingSetID: ActiveSetID(exerciseOrder: 0, setIndex: 0),
                incomingSetID: ActiveSetID(exerciseOrder: 0, setIndex: 1),
                completedExerciseOrder: nil
            )
    )
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
@Test func loggingFinalPendingSetCollapsesCompletedExercise() throws {
    let session = makeMultiExercisePendingSession()
    let squatSets = try #require(session.exercises.first { $0.order == 0 }?.sets)
    squatSets.forEach { $0.state = .logged }
    let finalSquatSet = try #require(squatSets.first { $0.index == 1 })
    let squat = try #require(finalSquatSet.exercise)
    let focus = ActiveSetFocusManager(session: session)

    focus.advanceAfterLog(finalSquatSet, in: session)

    #expect(focus.isCollapsed(squat))
}

@MainActor
@Test func loggingFinalPendingSetRecordsCollapseAndRiseTransition() throws {
    let session = makeMultiExercisePendingSession()
    let squatSets = try #require(session.exercises.first { $0.order == 0 }?.sets)
    squatSets.forEach { $0.state = .logged }
    let finalSquatSet = try #require(squatSets.first { $0.index == 1 })
    let focus = ActiveSetFocusManager(session: session)

    focus.advanceAfterLog(finalSquatSet, in: session)

    #expect(
        focus.activeSetTransition
            == ActiveSetTransition(
                kind: .collapseAndRise,
                outgoingSetID: ActiveSetID(exerciseOrder: 0, setIndex: 1),
                incomingSetID: ActiveSetID(exerciseOrder: 1, setIndex: 0),
                completedExerciseOrder: 0
            )
    )
}

@MainActor
@Test func reexpandingCompletedExercisePreservesCurrentFocusAndExpandsLoggedSetReview() throws {
    let session = makeMultiExercisePendingSession()
    let squatSets = try #require(session.exercises.first { $0.order == 0 }?.sets)
    squatSets.forEach { $0.state = .logged }
    let firstSquatSet = try #require(squatSets.first { $0.index == 0 })
    let finalSquatSet = try #require(squatSets.first { $0.index == 1 })
    let squat = try #require(finalSquatSet.exercise)
    let focus = ActiveSetFocusManager(session: session)

    focus.advanceAfterLog(finalSquatSet, in: session)
    focus.reexpand(squat)

    #expect(!focus.isCollapsed(squat))
    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))

    focus.focus(on: firstSquatSet)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(focus.expandedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))

    focus.focus(on: firstSquatSet)

    #expect(focus.expandedLoggedSetID == nil)
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
@Test func skippingActiveSetRecordsSoftFadeUpTransition() throws {
    let session = makePendingSession()
    let set = try #require(session.exercises.first?.sets.first { $0.index == 0 })
    let focus = ActiveSetFocusManager(session: session)

    set.state = .skipped
    focus.advanceAfterSkip(set, in: session)

    #expect(
        focus.activeSetTransition
            == ActiveSetTransition(
                kind: .softFadeUp,
                outgoingSetID: ActiveSetID(exerciseOrder: 0, setIndex: 0),
                incomingSetID: ActiveSetID(exerciseOrder: 0, setIndex: 1),
                completedExerciseOrder: nil
            )
    )
    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
}

@MainActor
@Test func skippingFinalPendingSetRecordsCollapseAndRiseTransition() throws {
    let session = makeMultiExercisePendingSession()
    let squatSets = try #require(session.exercises.first { $0.order == 0 }?.sets)
    squatSets.forEach { $0.state = .skipped }
    let finalSquatSet = try #require(squatSets.first { $0.index == 1 })
    let focus = ActiveSetFocusManager(session: session)

    focus.advanceAfterSkip(finalSquatSet, in: session)

    #expect(
        focus.activeSetTransition
            == ActiveSetTransition(
                kind: .collapseAndRise,
                outgoingSetID: ActiveSetID(exerciseOrder: 0, setIndex: 1),
                incomingSetID: ActiveSetID(exerciseOrder: 1, setIndex: 0),
                completedExerciseOrder: 0
            )
    )
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
    #expect(focus.scrollTargetID == nil)

    firstSquatSet.state = .logged
    focus.advanceAfterLog(firstSquatSet, in: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(focus.scrollTargetID == nil)
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
    #expect(focus.scrollTargetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(
        focus.activeSetTransition
            == ActiveSetTransition(
                kind: .collapseAndRise,
                outgoingSetID: ActiveSetID(exerciseOrder: 0, setIndex: 0),
                incomingSetID: ActiveSetID(exerciseOrder: 1, setIndex: 0),
                completedExerciseOrder: 0
            )
    )

    firstSquatSet.state = .logged
    focus.advanceAfterLog(firstSquatSet, in: session)

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(focus.scrollTargetID == nil)
}

@MainActor
@Test func activeSupersetSurfaceShowsBothSidesAndFocusesPairedExerciseNextPendingSet() throws {
    let session = makeMultiExercisePendingSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let focus = ActiveSetFocusManager(session: session)

    #expect(focus.createSuperset(with: [squat, bench], in: session))

    let initialSurface = try #require(focus.activeSupersetPresentation(in: session))
    #expect(initialSurface.sides.map(\.exerciseName) == ["Squat", "Bench Press"])
    #expect(initialSurface.sides.map(\.isActive) == [true, false])
    #expect(initialSurface.sides.map(\.nextSetText) == ["Set 1 of 2", "Set 1 of 1"])

    #expect(focus.focusNextSupersetSet(for: bench, in: session))

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    let switchedSurface = try #require(focus.activeSupersetPresentation(in: session))
    #expect(switchedSurface.sides.map(\.isActive) == [false, true])
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
@Test func creatingPlannedSupersetFormsSurfaceAndScrollTargetWithoutChangingFocus() throws {
    let session = makePlannedSupersetSession()
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let focus = ActiveSetFocusManager(session: session)

    #expect(focus.createSuperset(from: squat, to: bench, in: session))

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(focus.supersetScrollTargetOrder == 1)

    let surface = try #require(focus.supersetSections(in: session).first?.presentation)
    #expect(surface.activeSetID == nil)
    #expect(surface.containerExerciseOrder == 1)
    #expect(surface.sides.map(\.exerciseName) == ["Squat", "Bench Press"])
    #expect(surface.sides.map(\.isActive) == [false, false])
}

@MainActor
@Test func manualSupersetDismissRemovesSurfaceWithoutChangingSetLogs() throws {
    let session = makeMultiExercisePendingSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let log = SetLog(weight: .pounds(185), reps: 5, rpe: 7)
    firstSquatSet.setLog = log
    firstSquatSet.state = .logged
    let focus = ActiveSetFocusManager(session: session)

    #expect(focus.createSuperset(from: squat, to: bench, in: session))
    focus.dismissSuperset(containing: squat, in: session)

    #expect(focus.supersetSections(in: session).isEmpty)
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

    #expect(relaunchedFocus.supersetSections(in: session).isEmpty)
}
