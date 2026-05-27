import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func sessionCoordinatorContainer() throws -> ModelContainer {
    try ModelContainer(
        for: LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "session-coordinator-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

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

private func makePlannedPairingSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)

    let press = Exercise(name: "Press", baseName: "Press", cadence: nil, coachNote: nil, order: 0)
    press.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let squat = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 1)
    squat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let bench = Exercise(name: "Bench Press", baseName: "Bench Press", cadence: nil, coachNote: nil, order: 2)
    bench.sets = [
        ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    session.exercises = [bench, press, squat]
    return session
}

private func makeFourExercisePairingSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)

    let press = Exercise(name: "Press", baseName: "Press", cadence: nil, coachNote: nil, order: 0)
    press.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let squat = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 1)
    squat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let bench = Exercise(name: "Bench Press", baseName: "Bench Press", cadence: nil, coachNote: nil, order: 2)
    bench.sets = [
        ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let row = Exercise(name: "DB Row", baseName: "DB Row", cadence: nil, coachNote: nil, order: 3)
    row.sets = [
        ExerciseSet(index: 0, prescribedReps: "10", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    session.exercises = [row, bench, press, squat]
    return session
}

private func makeIntegratedCoordinatorSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)

    let squat = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)
    squat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending),
        ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    ]

    let bench = Exercise(name: "Bench Press", baseName: "Bench Press", cadence: nil, coachNote: nil, order: 1)
    bench.sets = [
        ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let row = Exercise(name: "DB Row", baseName: "DB Row", cadence: nil, coachNote: nil, order: 2)
    row.sets = [
        ExerciseSet(index: 0, prescribedReps: "10", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let pulldown = Exercise(name: "Lat Pulldown", baseName: "Lat Pulldown", cadence: nil, coachNote: nil, order: 3)
    pulldown.sets = [
        ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    session.exercises = [pulldown, row, bench, squat]
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
    let clock = ManualSessionTransitionClock()
    let coordinator = SessionCoordinator(session: session, transitionClock: clock)
    let firstBenchSet = try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })

    firstBenchSet.state = .logged
    coordinator.advanceAfterLog(firstBenchSet, in: session)
    #expect(coordinator.beginPairing(from: bench, in: session))
    #expect(coordinator.handlePairingTap(on: row, in: session) == .confirming)

    let items = coordinator.exerciseRenderItems(in: session)

    #expect(items.map { $0.exercise.order } == [0, 1, 2])
    #expect(items.map(\.isCollapsed) == [true, false, false])
    let expectedActiveSetID = ActiveSetID(exerciseOrder: 1, setIndex: 1)
    #expect(items.map(\.activeSetID) == [nil, expectedActiveSetID, nil])
    #expect(items.map { $0.activeSetTransition != nil } == [false, true, false])
    #expect(items.map(\.showsPairingGrip) == [true, true, true])
    #expect(items.map(\.pairingAvailability) == [.unavailable, .available, .available])
    #expect(items.map(\.isPairingConfirmation) == [false, false, true])
}

@MainActor
@Test func coordinatorBuildsOrderedRenderItemsWithSupersetsAndHiddenPairedExercises() throws {
    let session = makeFourExercisePairingSession()
    let coordinator = SessionCoordinator(session: session)
    let press = try #require(session.exercises.first { $0.order == 0 })
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let row = try #require(session.exercises.first { $0.order == 3 })

    #expect(coordinator.createSuperset(from: squat, to: row, in: session))

    let items = coordinator.renderItems(in: session)

    #expect(items.map(\.id) == ["exercise-0", "superset-1", "exercise-2", "hidden-paired-exercise-3"])
    guard case .exercise(let firstExercise) = items[0] else {
        Issue.record("Expected ordinary Exercise render item for Press")
        return
    }
    guard case .superset(let superset) = items[1] else {
        Issue.record("Expected Superset render item for Squat and DB Row")
        return
    }
    guard case .exercise(let thirdExercise) = items[2] else {
        Issue.record("Expected ordinary Exercise render item for Bench Press")
        return
    }
    guard case .hiddenPairedExercise(let hidden) = items[3] else {
        Issue.record("Expected hidden paired Exercise placeholder for DB Row")
        return
    }

    #expect(firstExercise.exercise === press)
    #expect(superset.exercises.map(\.order) == [1, 3])
    #expect(superset.presentation.containerExerciseOrder == 1)
    #expect(thirdExercise.exercise === bench)
    #expect(hidden.exercise === row)
    #expect(hidden.containerExerciseOrder == 1)
}

@MainActor
@Test func coordinatorRenderItemsCarryLastPerformedPresentations() throws {
    let container = try sessionCoordinatorContainer()
    let context = container.mainContext
    context.insert(
        LastPerformedEntry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            result: SetLog(weight: .pounds(185), reps: 6, rpe: 7),
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "W3 D2"
        )
    )
    try context.save()
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session)

    let items = coordinator.renderItems(
        in: session,
        lastPerformedIndex: LastPerformedIndex(context: context)
    )

    let benchConfig = try #require(items.compactMap(\.exerciseConfig).first { $0.exercise.order == 1 })
    #expect(benchConfig.lastPerformedPresentation?.resultText == "185x6@7")
    #expect(benchConfig.lastPerformedPresentation?.sourceText == "W3 D2")
    withExtendedLifetime(container) {}
}

@MainActor
@Test func coordinatorBeginsPairingOnlyFromEligibleExercise() throws {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session)
    let completedSquat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })

    #expect(!coordinator.beginPairing(from: completedSquat, in: session))
    #expect(coordinator.pairingMode == .inactive)

    #expect(coordinator.beginPairing(from: bench, in: session))
    #expect(coordinator.pairingMode == .selecting(sourceOrder: 1))
}

@MainActor
@Test func coordinatorHandlesSourceAndUnavailablePairingTaps() throws {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session)
    let completedSquat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })

    #expect(coordinator.beginPairing(from: bench, in: session))
    #expect(coordinator.handlePairingTap(on: completedSquat, in: session) == .unavailable)
    #expect(coordinator.pairingMode == .selecting(sourceOrder: 1))

    #expect(coordinator.handlePairingTap(on: bench, in: session) == .cancelled)
    #expect(coordinator.pairingMode == .inactive)
}

@MainActor
@Test func coordinatorSourceTapCancelsPairingConfirmation() throws {
    let session = makeCoordinatorSession()
    let clock = ManualSessionTransitionClock()
    let coordinator = SessionCoordinator(session: session, transitionClock: clock)
    let completedSquat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })

    #expect(coordinator.beginPairing(from: bench, in: session))
    #expect(coordinator.handlePairingTap(on: row, in: session) == .confirming)
    #expect(coordinator.handlePairingTap(on: completedSquat, in: session) == .unavailable)
    #expect(coordinator.pairingMode == .confirming(sourceOrder: 1, targetOrder: 2))

    #expect(coordinator.handlePairingTap(on: bench, in: session) == .cancelled)
    #expect(coordinator.pairingMode == .inactive)
    #expect(coordinator.supersetSections(in: session).isEmpty)
}

@MainActor
@Test func coordinatorCreatesSupersetAfterClockControlledPairingConfirmation() async throws {
    let session = makePlannedPairingSession()
    let clock = ManualSessionTransitionClock()
    let coordinator = SessionCoordinator(session: session, transitionClock: clock)
    let initialActiveSetID = coordinator.activeSetID
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })

    #expect(coordinator.beginPairing(from: squat, in: session))
    #expect(coordinator.handlePairingTap(on: bench, in: session) == .confirming)
    #expect(coordinator.pairingMode == .confirming(sourceOrder: 1, targetOrder: 2))
    #expect(coordinator.supersetSections(in: session).isEmpty)

    await clock.waitForSleep()

    let expectedDuration = Duration.nanoseconds(Int64((Theme.pairingConfirmationDuration * 1_000_000_000).rounded()))
    #expect(clock.sleptDurations == [expectedDuration])
    #expect(coordinator.supersetSections(in: session).isEmpty)

    clock.advance()
    await Task.yield()

    #expect(coordinator.pairingMode == .inactive)
    #expect(coordinator.activeSetID == initialActiveSetID)
    #expect(coordinator.supersetScrollTargetOrder == 1)
    let section = try #require(coordinator.supersetSections(in: session).first)
    #expect(section.exercises.map(\.order) == [1, 2])
}

@MainActor
@Test func coordinatorDismissesSupersetClearsPairingModeAndReconcilesFocus() throws {
    let session = makeFourExercisePairingSession()
    let coordinator = SessionCoordinator(session: session)
    let press = try #require(session.exercises.first { $0.order == 0 })
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })

    #expect(coordinator.createSuperset(from: press, to: squat, in: session))
    #expect(coordinator.beginPairing(from: bench, in: session))

    coordinator.dismissSuperset(containing: press, in: session)

    #expect(coordinator.pairingMode == .inactive)
    #expect(coordinator.supersetSections(in: session).isEmpty)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
}

@MainActor
@Test func coordinatorFocusesPairedExerciseNextPendingSetAndScrollTarget() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(session: session)
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })

    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))
    #expect(coordinator.focusNextSupersetSet(for: bench, in: session))

    let expectedSetID = ActiveSetID(exerciseOrder: 2, setIndex: 0)
    #expect(coordinator.activeSetID == expectedSetID)
    #expect(coordinator.scrollTargetID == expectedSetID)
    #expect(coordinator.supersetScrollTargetOrder == nil)
}

@MainActor
@Test func coordinatorPreservesCurrentSessionFlowThroughRenderItems() throws {
    let session = makeIntegratedCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(session: session, logging: logging, sync: sync)
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let finalSquatSet = try #require(squat.sets.first { $0.index == 1 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let squatLog = SetLog(weight: .pounds(315), reps: 5, rpe: 7)

    coordinator.log(firstSquatSet, as: squatLog)

    #expect(firstSquatSet.state == .logged)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
    #expect(sync.flushRequestCount == 1)

    coordinator.deleteLog(for: firstSquatSet)

    #expect(firstSquatSet.state == .pending)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(coordinator.exerciseRenderItems(in: session).first?.isCollapsed == false)

    coordinator.log(firstSquatSet, as: squatLog)
    coordinator.skip(finalSquatSet)

    #expect(finalSquatSet.state == .skipped)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    let afterSquatItems = coordinator.renderItems(in: session)
    let completedSquat = try #require(afterSquatItems.compactMap(\.exerciseConfig).first { $0.exercise.order == 0 })
    #expect(completedSquat.isCollapsed)

    #expect(coordinator.createSuperset(from: bench, to: row, in: session))

    let pairedItems = coordinator.renderItems(in: session)
    #expect(pairedItems.map(\.id) == ["exercise-0", "superset-1", "hidden-paired-exercise-2", "exercise-3"])
    let activeSuperset = try #require(coordinator.supersetSections(in: session).first?.presentation)
    #expect(activeSuperset.activeExerciseOrder == 1)

    #expect(coordinator.focusNextSupersetSet(for: row, in: session))
    let focusedSuperset = try #require(coordinator.supersetSections(in: session).first?.presentation)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(focusedSuperset.activeExerciseOrder == 2)

    coordinator.dismissSuperset(containing: row, in: session)

    #expect(coordinator.supersetSections(in: session).isEmpty)
    #expect(coordinator.renderItems(in: session).map(\.id) == ["exercise-0", "exercise-1", "exercise-2", "exercise-3"])
    #expect(logging.loggedSets.map(\.set) == [firstSquatSet, firstSquatSet])
    #expect(logging.skippedSets == [finalSquatSet])
    #expect(logging.deletedSets == [firstSquatSet])
    #expect(sync.reportedErrors.isEmpty)
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
