import Testing

@testable import WorkoutTracker

private func makeCoordinatorSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)

    let completedSquat = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)
    completedSquat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
    ]

    let bench = Exercise(name: "Bench Press", baseName: "Bench Press", cadence: nil, coachNote: nil, order: 1)
    let firstBenchSet = ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    let secondBenchSet = ExerciseSet(index: 1, prescribedReps: "6", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    bench.sets = [firstBenchSet, secondBenchSet]

    let row = Exercise(name: "DB Row", baseName: "DB Row", cadence: nil, coachNote: nil, order: 2)
    row.sets = [
        ExerciseSet(index: 0, prescribedReps: "10", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    session.exercises = [row, bench, completedSquat]
    return session
}

@MainActor
@Test func coordinatorBindExposesInitialFocusThroughCoordinatorInterface() {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator()

    coordinator.bind(to: session)

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func coordinatorBuildsOrdinaryExerciseRenderItemsInSessionOrder() throws {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session)
    let firstBenchSet = try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 0 })

    firstBenchSet.state = .logged
    coordinator.advanceAfterLog(firstBenchSet, in: session)

    let items = coordinator.exerciseRenderItems(
        in: session,
        pairingSourceOrder: 1,
        pairingConfirmationOrder: 2
    )

    #expect(items.map { $0.exercise.order } == [0, 1, 2])
    #expect(items.map(\.isCollapsed) == [true, false, false])
    let expectedActiveSetID = ActiveSetID(exerciseOrder: 1, setIndex: 1)
    #expect(items.map(\.activeSetID) == [expectedActiveSetID, expectedActiveSetID, expectedActiveSetID])
    #expect(items.allSatisfy { $0.activeSetTransition != nil })
    #expect(items.map(\.showsPairingGrip) == [true, true, true])
    #expect(items.map(\.pairingAvailability) == [.unavailable, .available, .available])
    #expect(items.map(\.isPairingConfirmation) == [false, false, true])
}
