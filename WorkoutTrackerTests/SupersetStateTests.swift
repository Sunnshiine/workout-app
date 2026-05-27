import Testing

@testable import WorkoutTracker

private func makeSupersetSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)
    let squat = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)
    squat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    ]
    let bench = Exercise(name: "Bench Press", baseName: "Bench Press", cadence: nil, coachNote: nil, order: 1)
    bench.sets = [
        ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 1, prescribedReps: "6", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    ]
    let row = Exercise(name: "DB Row", baseName: "DB Row", cadence: nil, coachNote: nil, order: 2)
    row.sets = [
        ExerciseSet(index: 0, prescribedReps: "10", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]
    session.exercises = [squat, bench, row]
    return session
}

@MainActor
@Test func supersetEligibilityRequiresTwoCurrentSessionExercisesWithPendingSetsAndNoExistingPair() throws {
    let session = makeSupersetSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let otherSessionExercise = Exercise(name: "Lat Pulldown", baseName: "Lat Pulldown", cadence: nil, coachNote: nil, order: 3)
    otherSessionExercise.sets = [
        ExerciseSet(index: 0, prescribedReps: "10", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]
    let state = SupersetState()

    #expect(state.canCreateSuperset(with: [squat, bench], in: session))
    #expect(!state.canCreateSuperset(with: [squat], in: session))
    #expect(!state.canCreateSuperset(with: [squat, bench, row], in: session))
    #expect(!state.canCreateSuperset(with: [squat, squat], in: session))
    #expect(!state.canCreateSuperset(with: [squat, otherSessionExercise], in: session))

    bench.sets.forEach { $0.state = .logged }

    #expect(!state.canCreateSuperset(with: [squat, bench], in: session))

    bench.sets[0].state = .pending
    #expect(state.createSuperset(with: [squat, bench], in: session))
    #expect(!state.canCreateSuperset(with: [bench, row], in: session))
    #expect(state.canCreateSuperset(with: [squat, bench], in: session) == false)
}

@MainActor
@Test func supersetProgressionAlternatesToOtherExercisesNextPendingSet() throws {
    let session = makeSupersetSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let state = SupersetState()
    state.createSuperset(with: [squat, bench], in: session)

    firstBenchSet.state = .skipped
    firstSquatSet.state = .logged

    #expect(
        state.nextSetID(after: firstSquatSet, in: session)
            == ActiveSetID(exerciseOrder: 1, setIndex: 1)
    )
}

@MainActor
@Test func athleteCanManuallyFocusEitherExercisesNextPendingSetInsideActiveSuperset() throws {
    let session = makeSupersetSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let state = SupersetState()
    state.createSuperset(with: [squat, bench], in: session)

    squat.sets[0].state = .logged

    #expect(
        state.focusNextPendingSet(for: squat, in: session)
            == ActiveSetID(exerciseOrder: 0, setIndex: 1)
    )
    #expect(
        state.focusNextPendingSet(for: bench, in: session)
            == ActiveSetID(exerciseOrder: 1, setIndex: 0)
    )
    #expect(state.focusNextPendingSet(for: row, in: session) == nil)
}

@MainActor
@Test func supersetDissolvesManuallyOrWhenEitherExerciseHasNoPendingSetsAndDoesNotReformAfterDelete() throws {
    let session = makeSupersetSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let state = SupersetState()

    state.createSuperset(with: [squat, bench], in: session)
    state.dismissSuperset(containing: squat)

    #expect(state.supersetCount == 0)
    #expect(!state.isPaired(squat))
    #expect(!state.isPaired(bench))

    state.createSuperset(with: [squat, bench], in: session)
    squat.sets.forEach { $0.state = .logged }
    state.refresh(in: session)

    #expect(state.supersetCount == 0)
    #expect(!state.isPaired(squat))
    #expect(!state.isPaired(bench))

    squat.sets[0].state = .pending
    state.refresh(in: session)

    #expect(state.supersetCount == 0)
    #expect(!state.isPaired(squat))
    #expect(!state.isPaired(bench))
}

@MainActor
@Test func plannedSupersetActivatesOnlyWhenNormalFocusReachesEitherPairedExercise() throws {
    let session = makeSupersetSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let state = SupersetState()
    let rowFocus = ActiveSetID(exerciseOrder: row.order, setIndex: 0)
    let squatFocus = ActiveSetID(exerciseOrder: squat.order, setIndex: 0)

    state.createSuperset(with: [squat, bench], in: session)

    #expect(state.focusedSetID(whenNormalFocusIs: rowFocus, in: session) == rowFocus)
    #expect(state.focusedSetID(whenNormalFocusIs: squatFocus, in: session) == squatFocus)

    let activeState = SupersetState()
    activeState.createSuperset(with: [squat, bench], in: session, currentActiveSetID: squatFocus)

    #expect(activeState.focusedSetID(whenNormalFocusIs: rowFocus, in: session) == squatFocus)
}

@MainActor
@Test func supersetReconcilesAcrossLocalSyncRefreshUsingExerciseIdentity() throws {
    let session = makeSupersetSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let state = SupersetState()
    state.createSuperset(with: [squat, bench], in: session)

    let refreshedSession = makeSupersetSession()
    let refreshedSquat = try #require(refreshedSession.exercises.first { $0.order == 0 })
    let refreshedBench = try #require(refreshedSession.exercises.first { $0.order == 1 })

    state.refresh(in: refreshedSession)

    #expect(state.supersetCount == 1)
    #expect(state.isPaired(refreshedSquat))
    #expect(state.isPaired(refreshedBench))
}

@MainActor
@Test func supersetStateDoesNotMutateSetLogsOrSetStates() throws {
    let session = makeSupersetSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let loggedSet = try #require(squat.sets.first { $0.index == 1 })
    loggedSet.state = .logged
    loggedSet.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: 7)
    let state = SupersetState()

    state.createSuperset(with: [squat, bench], in: session, currentActiveSetID: ActiveSetID(exerciseOrder: 0, setIndex: 0))
    _ = state.focusNextPendingSet(for: bench, in: session)
    state.dismissSuperset(containing: squat)

    #expect(firstSquatSet.state == .pending)
    #expect(firstBenchSet.state == .pending)
    #expect(loggedSet.state == .logged)
    #expect(loggedSet.setLog == SetLog(weight: .pounds(185), reps: 5, rpe: 7))
}
