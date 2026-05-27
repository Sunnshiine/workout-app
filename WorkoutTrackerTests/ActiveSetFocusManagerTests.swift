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
@Test func reexpandingCompletedExercisePreservesCurrentFocusAndAllowsSwapFocus() throws {
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

    #expect(focus.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
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
