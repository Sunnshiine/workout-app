import Testing

@testable import WorkoutTracker

private enum TestLoggingError: Error, Equatable {
    case failed
}

@MainActor
private final class SpySessionLoggingAdapter: SessionLoggingAdapter {
    private(set) var loggedSets: [(set: ExerciseSet, log: SetLog)] = []
    private(set) var skippedSets: [ExerciseSet] = []
    private(set) var deletedSets: [ExerciseSet] = []
    var error: TestLoggingError?

    func log(_ set: ExerciseSet, as log: SetLog) throws {
        if let error { throw error }
        loggedSets.append((set, log))
        set.setLog = log
        set.state = .logged
    }

    func skip(_ set: ExerciseSet) throws {
        if let error { throw error }
        skippedSets.append(set)
        set.setLog = nil
        set.state = .skipped
    }

    func deleteLog(for set: ExerciseSet) throws {
        if let error { throw error }
        deletedSets.append(set)
        set.setLog = nil
        set.state = .pending
    }
}

@MainActor
private final class SpySessionSyncAdapter: SessionSyncAdapter {
    private(set) var reportedErrors: [String] = []
    private(set) var flushRequestCount = 0

    func reportLocalWriteFailure(_ error: any Error) {
        reportedErrors.append(String(describing: error))
    }

    func requestPendingWriteFlush() {
        flushRequestCount += 1
    }
}

@MainActor
private final class ManualSessionTransitionClock: SessionTransitionClock {
    private(set) var sleptDurations: [Duration] = []
    private var sleepContinuations: [CheckedContinuation<Void, Never>] = []
    private var sleepWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async {
        sleptDurations.append(duration)
        let waiters = sleepWaiters
        sleepWaiters = []
        waiters.forEach { $0.resume() }

        await withCheckedContinuation { continuation in
            sleepContinuations.append(continuation)
        }
    }

    func waitForSleep() async {
        if !sleptDurations.isEmpty { return }

        await withCheckedContinuation { continuation in
            sleepWaiters.append(continuation)
        }
    }

    func advance() {
        let continuations = sleepContinuations
        sleepContinuations = []
        continuations.forEach { $0.resume() }
    }
}

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

private func makeSingleSetSession(dayNumber: Int) -> (session: Session, set: ExerciseSet) {
    let session = Session(dayNumber: dayNumber, date: nil)
    let exercise = Exercise(name: "Bench Press", baseName: "Bench Press", cadence: nil, coachNote: nil, order: 0)
    let set = ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    exercise.sets = [set]
    session.exercises = [exercise]
    return (session, set)
}

private struct CoordinatorActionFixture {
    let session: Session
    let coordinator: SessionCoordinator
    let logging: SpySessionLoggingAdapter
    let sync: SpySessionSyncAdapter
    let clock: ManualSessionTransitionClock
}

@MainActor
private func makeActionFixture() throws -> CoordinatorActionFixture {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualSessionTransitionClock()
    let coordinator = SessionCoordinator(
        session: session,
        logging: logging,
        sync: sync,
        transitionClock: clock
    )
    return CoordinatorActionFixture(
        session: session,
        coordinator: coordinator,
        logging: logging,
        sync: sync,
        clock: clock
    )
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

@MainActor
@Test func loggingSetUsesAdaptersAdvancesFocusStartsRetiringTransitionAndFlushes() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: 7)

    fixture.coordinator.log(firstBenchSet, as: log)

    #expect(fixture.logging.loggedSets.count == 1)
    #expect(fixture.logging.loggedSets.first?.set === firstBenchSet)
    #expect(fixture.logging.loggedSets.first?.log == log)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
    let transition = try #require(fixture.coordinator.activeSetTransition)
    #expect(
        transition
            == ActiveSetTransition(
                kind: .momentumFlow,
                outgoingSetID: ActiveSetID(exerciseOrder: 1, setIndex: 0),
                incomingSetID: ActiveSetID(exerciseOrder: 1, setIndex: 1),
                completedExerciseOrder: nil
            )
    )
    #expect(fixture.coordinator.retiringTransition == transition)
    #expect(fixture.sync.flushRequestCount == 1)
    #expect(fixture.sync.reportedErrors.isEmpty)
}

@MainActor
@Test func skippingSetUsesAdaptersAdvancesFocusStartsRetiringTransitionAndFlushes() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    fixture.coordinator.skip(firstBenchSet)

    #expect(fixture.logging.skippedSets.count == 1)
    #expect(fixture.logging.skippedSets.first === firstBenchSet)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
    let transition = try #require(fixture.coordinator.activeSetTransition)
    #expect(
        transition
            == ActiveSetTransition(
                kind: .softFadeUp,
                outgoingSetID: ActiveSetID(exerciseOrder: 1, setIndex: 0),
                incomingSetID: ActiveSetID(exerciseOrder: 1, setIndex: 1),
                completedExerciseOrder: nil
            )
    )
    #expect(fixture.coordinator.retiringTransition == transition)
    #expect(fixture.sync.flushRequestCount == 1)
    #expect(fixture.sync.reportedErrors.isEmpty)
}

@MainActor
@Test func deletingSetLogUsesAdaptersFocusesDeletedSetClearsRetiringTransitionAndFlushes() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: 7)
    fixture.coordinator.log(firstBenchSet, as: log)

    fixture.coordinator.deleteLog(for: firstBenchSet)

    #expect(fixture.logging.deletedSets.count == 1)
    #expect(fixture.logging.deletedSets.first === firstBenchSet)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(fixture.coordinator.activeSetTransition == nil)
    #expect(fixture.coordinator.retiringTransition == nil)
    #expect(fixture.sync.flushRequestCount == 2)
    #expect(fixture.sync.reportedErrors.isEmpty)
}

@MainActor
@Test func loggingAdapterErrorReportsFailureWithoutAdvancingFocusOrFlushing() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: 7)
    fixture.logging.error = .failed

    fixture.coordinator.log(firstBenchSet, as: log)

    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(fixture.coordinator.activeSetTransition == nil)
    #expect(fixture.coordinator.retiringTransition == nil)
    #expect(firstBenchSet.state == .pending)
    #expect(fixture.sync.flushRequestCount == 0)
    #expect(fixture.sync.reportedErrors == ["failed"])
}

@MainActor
@Test func loggingSetFromDifferentSessionRebindsBeforeAdvancingFocus() throws {
    let old = makeSingleSetSession(dayNumber: 1)
    let new = makeSingleSetSession(dayNumber: 2)
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(session: old.session, logging: logging, sync: sync)
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: 7)

    coordinator.log(new.set, as: log)

    #expect(coordinator.session === new.session)
    #expect(logging.loggedSets.first?.set === new.set)
    #expect(new.set.state == .logged)
    #expect(old.set.state == .pending)
    #expect(coordinator.activeSetTransition?.outgoingSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(sync.flushRequestCount == 1)
}

@MainActor
@Test func deletingSetFromDifferentSessionRebindsBeforeFocusingDeletedSet() throws {
    let old = makeSingleSetSession(dayNumber: 1)
    let new = makeSingleSetSession(dayNumber: 2)
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(session: old.session, logging: logging, sync: sync)
    new.set.state = .logged
    new.set.setLog = SetLog(weight: .pounds(185), reps: 6, rpe: 7)

    coordinator.deleteLog(for: new.set)

    #expect(coordinator.session === new.session)
    #expect(logging.deletedSets.first === new.set)
    #expect(new.set.state == .pending)
    #expect(old.set.state == .pending)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(coordinator.activeSetTransition == nil)
    #expect(coordinator.retiringTransition == nil)
    #expect(sync.flushRequestCount == 1)
}

@MainActor
@Test func transitionRetirementUsesInjectedClockWithoutRealSleep() async throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    fixture.coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: 7))
    let transition = try #require(fixture.coordinator.retiringTransition)
    await fixture.clock.waitForSleep()

    #expect(fixture.clock.sleptDurations == [.nanoseconds(650_000_000)])
    #expect(fixture.coordinator.retiringTransition == transition)
    #expect(fixture.coordinator.activeSetTransition == transition)

    fixture.clock.advance()
    await Task.yield()

    #expect(fixture.coordinator.retiringTransition == nil)
    #expect(fixture.coordinator.activeSetTransition == nil)
}
