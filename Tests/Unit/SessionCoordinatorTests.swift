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

@MainActor
private final class ManualCoordinatorRestClock: RestClock {
    var now: Date

    init(now: Date) {
        self.now = now
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

@MainActor
private func connectCoordinatorWeek(_ sessions: [Session]) {
    let week = Week(number: 1)
    week.sessions = sessions
}

private struct CoordinatorActionFixture {
    let session: Session
    let coordinator: SessionCoordinator
    let logging: SpySessionLoggingAdapter
    let sync: SpySessionSyncAdapter
    let clock: ManualSessionTransitionClock
}

private struct CoordinatorRestActionFixture {
    let session: Session
    let coordinator: SessionCoordinator
    let restTimer: RestTimer
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
private func makeRestActionFixture() throws -> CoordinatorRestActionFixture {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(session: session, logging: logging, sync: sync, restTimer: restTimer)
    return CoordinatorRestActionFixture(
        session: session,
        coordinator: coordinator,
        restTimer: restTimer
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
@Test func coordinatorExpandsLoggedSetReviewWithoutChangingActivePendingSet() throws {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session)
    let completedSquatSet = try #require(session.exercises.first { $0.order == 0 }?.sets.first)

    coordinator.focus(on: completedSquatSet)

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(coordinator.expandedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(coordinator.visualFocusOwner == .loggedSetReview(ActiveSetID(exerciseOrder: 0, setIndex: 0)))

    let renderItems = coordinator.exerciseRenderItems(in: session)
    let squatConfig = try #require(renderItems.first { $0.exercise.order == 0 })
    let benchConfig = try #require(renderItems.first { $0.exercise.order == 1 })
    #expect(squatConfig.activeSetID == nil)
    #expect(squatConfig.expandedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(squatConfig.visualFocusOwner == .loggedSetReview(ActiveSetID(exerciseOrder: 0, setIndex: 0)))
    #expect(benchConfig.activeSetID == nil)
    #expect(benchConfig.visualFocusOwner == nil)
    #expect(renderItems.filter { $0.visualFocusOwner != nil }.count == 1)

    coordinator.focus(on: completedSquatSet)

    #expect(coordinator.expandedLoggedSetID == nil)
    #expect(coordinator.visualFocusOwner == .activeSet(ActiveSetID(exerciseOrder: 1, setIndex: 0)))
    #expect(
        coordinator.exerciseRenderItems(in: session).map(\.visualFocusOwner)
            == [nil, .activeSet(ActiveSetID(exerciseOrder: 1, setIndex: 0)), nil]
    )
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
        lastPerformedLookup: LastPerformedIndex(context: context).snapshot()
    )

    let benchConfig = try #require(items.compactMap(\.exerciseConfig).first { $0.exercise.order == 1 })
    #expect(benchConfig.lastPerformedPresentation?.resultText == "185x6@7")
    #expect(benchConfig.lastPerformedPresentation?.sourceText == "W3 D2")
    withExtendedLifetime(container) {}
}

@MainActor
@Test func coordinatorRenderItemsBuildFromPureLastPerformedLookup() throws {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session)
    let lookup = LastPerformedLookupSnapshot(
        exactMatches: [
            "Bench Press": LastPerformedLookupEntry(
                resultText: "185x6@7",
                sourceText: "W3 D2",
                performedOn: Date(timeIntervalSinceReferenceDate: 100)
            )
        ]
    )

    let items = coordinator.renderItems(in: session, lastPerformedLookup: lookup)

    let benchConfig = try #require(items.compactMap(\.exerciseConfig).first { $0.exercise.order == 1 })
    #expect(benchConfig.lastPerformedPresentation?.resultText == "185x6@7")
    #expect(benchConfig.lastPerformedPresentation?.sourceText == "W3 D2")
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
@Test func coordinatorSupersetSideSwitchUsesInjectedFocusAnimationWithoutTransition() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(session: session)
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    var animationCallCount = 0
    let animation: SessionFocusAnimation = { update in
        animationCallCount += 1
        update()
    }

    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))
    #expect(coordinator.focusNextSupersetSet(for: bench, in: session, animateFocus: animation))

    let expectedSetID = ActiveSetID(exerciseOrder: 2, setIndex: 0)
    #expect(animationCallCount == 1)
    #expect(coordinator.activeSetID == expectedSetID)
    #expect(coordinator.scrollTargetID == expectedSetID)
    #expect(coordinator.activeSetTransition == nil)
}

@MainActor
@Test func coordinatorFailedSupersetSideSwitchDoesNotUseInjectedFocusAnimation() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(session: session)
    let press = try #require(session.exercises.first { $0.order == 0 })
    var animationCallCount = 0
    let animation: SessionFocusAnimation = { update in
        animationCallCount += 1
        update()
    }

    #expect(!coordinator.focusNextSupersetSet(for: press, in: session, animateFocus: animation))

    #expect(animationCallCount == 0)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(coordinator.scrollTargetID == nil)
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
@Test func loggingSetStartsConfiguredStandardRestTimer() throws {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: session,
        logging: logging,
        sync: sync,
        restTimer: restTimer,
        standardRestDuration: { 210 }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: 7))

    #expect(restTimer.deadline == Date(timeIntervalSinceReferenceDate: 2_210))
    #expect(restTimer.remaining == 210)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func loggingAnotherSetRestartsExistingRestTimer() throws {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: session,
        logging: logging,
        sync: sync,
        restTimer: restTimer,
        standardRestDuration: { 210 }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let rowSet = try #require(session.exercises.first { $0.order == 2 }?.sets.first)

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: 7))
    clock.now.addTimeInterval(60)
    coordinator.log(rowSet, as: SetLog(weight: .pounds(95), reps: 10, rpe: 7))

    #expect(restTimer.deadline == Date(timeIntervalSinceReferenceDate: 2_270))
    #expect(restTimer.remaining == 210)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(restTimer.restartRevision == 2)
}

@MainActor
@Test func deletingOriginSetCancelsRunningRestTimer() throws {
    let fixture = try makeRestActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let secondBenchSet = try #require(bench.sets.first { $0.index == 1 })

    fixture.coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: 7))
    fixture.coordinator.deleteLog(for: secondBenchSet)

    #expect(fixture.restTimer.isRunning)

    fixture.coordinator.deleteLog(for: firstBenchSet)

    #expect(fixture.restTimer.deadline == nil)
    #expect(fixture.restTimer.origin == nil)
    #expect(!fixture.restTimer.isRunning)
}

@MainActor
@Test func cancellingSessionRestForMoveOnDismissesRunningRestTimer() throws {
    let fixture = try makeRestActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    fixture.coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: 7))
    fixture.coordinator.cancelRestForSessionExit()

    #expect(fixture.restTimer.deadline == nil)
    #expect(fixture.restTimer.origin == nil)
    #expect(!fixture.restTimer.isRunning)
}

@MainActor
@Test func loggingLastCurrentWeekPendingSetDoesNotStartRestTimer() throws {
    let current = makeSingleSetSession(dayNumber: 1)
    connectCoordinatorWeek([current.session])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: current.session,
        logging: logging,
        sync: sync,
        restTimer: restTimer,
        standardRestDuration: { 210 }
    )

    coordinator.log(current.set, as: SetLog(weight: .pounds(185), reps: 6, rpe: 7))

    #expect(restTimer.deadline == nil)
    #expect(restTimer.origin == nil)
    #expect(logging.loggedSets.map(\.set) == [current.set])
    #expect(sync.flushRequestCount == 1)
}

@MainActor
@Test func loggingDayLastSetStartsRestWhenMakeupOpenExerciseRemains() throws {
    let current = makeSingleSetSession(dayNumber: 1)
    let makeup = makeSingleSetSession(dayNumber: 2)
    connectCoordinatorWeek([current.session, makeup.session])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: current.session,
        logging: logging,
        sync: sync,
        restTimer: restTimer,
        standardRestDuration: { 210 }
    )

    coordinator.log(current.set, as: SetLog(weight: .pounds(185), reps: 6, rpe: 7))

    #expect(restTimer.deadline == Date(timeIntervalSinceReferenceDate: 2_210))
    #expect(restTimer.remaining == 210)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 0, setIndex: 0))
}

@MainActor
@Test func bindingSheetOriginLogsDoesNotStartRestTimer() {
    let current = makeSingleSetSession(dayNumber: 1)
    current.set.state = .logged
    current.set.unstructuredSetLog = "185 for reps"
    connectCoordinatorWeek([current.session])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: nil,
        logging: logging,
        sync: sync,
        restTimer: restTimer,
        standardRestDuration: { 210 }
    )

    coordinator.bind(to: current.session)

    #expect(restTimer.deadline == nil)
    #expect(logging.loggedSets.isEmpty)
    #expect(sync.flushRequestCount == 0)
}

@MainActor
@Test func editSkipAndDeleteDoNotStartRestTimer() throws {
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: 7)

    let editFixture = try makeRestActionFixture()
    let squatSet = try #require(editFixture.session.exercises.first { $0.order == 0 }?.sets.first)
    editFixture.coordinator.updateLoggedSet(squatSet, as: log)
    #expect(editFixture.restTimer.deadline == nil)

    let skipFixture = try makeRestActionFixture()
    let skipSet = try #require(skipFixture.session.exercises.first { $0.order == 1 }?.sets.first)
    skipFixture.coordinator.skip(skipSet)
    #expect(skipFixture.restTimer.deadline == nil)

    let deleteFixture = try makeRestActionFixture()
    let deleteSet = try #require(deleteFixture.session.exercises.first { $0.order == 1 }?.sets.first)
    deleteSet.state = .logged
    deleteSet.setLog = log
    deleteFixture.coordinator.deleteLog(for: deleteSet)
    #expect(deleteFixture.restTimer.deadline == nil)
}

@MainActor
@Test func updatingLoggedSetUsesAdaptersWithoutAdvancingActivePendingSet() throws {
    let fixture = try makeActionFixture()
    let squatSet = try #require(fixture.session.exercises.first { $0.order == 0 }?.sets.first)
    let updatedLog = SetLog(weight: .pounds(205), reps: 5, rpe: 8)

    fixture.coordinator.focus(on: squatSet)
    fixture.coordinator.updateLoggedSet(squatSet, as: updatedLog)

    #expect(fixture.logging.loggedSets.count == 1)
    #expect(fixture.logging.loggedSets.first?.set === squatSet)
    #expect(fixture.logging.loggedSets.first?.log == updatedLog)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(fixture.coordinator.expandedLoggedSetID == nil)
    #expect(fixture.coordinator.visualFocusOwner == .activeSet(ActiveSetID(exerciseOrder: 1, setIndex: 0)))
    #expect(fixture.coordinator.savedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(fixture.coordinator.activeSetTransition == nil)
    #expect(fixture.sync.flushRequestCount == 1)
    #expect(fixture.sync.reportedErrors.isEmpty)
}

@MainActor
@Test func openingLoggedSetReviewClearsRetiringActiveCard() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    fixture.coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: 7))
    #expect(fixture.coordinator.retiringTransition != nil)

    fixture.coordinator.focus(on: firstBenchSet)

    #expect(fixture.coordinator.visualFocusOwner == .loggedSetReview(ActiveSetID(exerciseOrder: 1, setIndex: 0)))
    #expect(fixture.coordinator.retiringTransition == nil)
    let benchConfig = try #require(fixture.coordinator.exerciseRenderItems(in: fixture.session).first { $0.exercise.order == 1 })
    #expect(benchConfig.expandedLoggedSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(benchConfig.retiringTransition == nil)
}

@MainActor
@Test func pendingFocusUsesInjectedAnimationForEachRetargetWithoutActiveSetTransition() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let secondBenchSet = try #require(bench.sets.first { $0.index == 1 })
    let rowSet = try #require(fixture.session.exercises.first { $0.order == 2 }?.sets.first)
    var animationCallCount = 0
    let animation: SessionFocusAnimation = { update in
        animationCallCount += 1
        update()
    }

    fixture.coordinator.focus(on: rowSet, animateFocus: animation)
    fixture.coordinator.focus(on: secondBenchSet, animateFocus: animation)
    fixture.coordinator.focus(on: firstBenchSet, animateFocus: animation)

    #expect(animationCallCount == 3)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(fixture.coordinator.activeSetTransition == nil)
    #expect(fixture.coordinator.retiringTransition == nil)
}

@MainActor
@Test func updatingPreviousLoggedSetDoesNotCollapseNewlyExpandedLoggedSet() throws {
    let fixture = try makeActionFixture()
    let squatSet = try #require(fixture.session.exercises.first { $0.order == 0 }?.sets.first)
    let rowSet = try #require(fixture.session.exercises.first { $0.order == 2 }?.sets.first)
    rowSet.state = .logged
    let updatedLog = SetLog(weight: .pounds(205), reps: 5, rpe: 8)

    fixture.coordinator.focus(on: squatSet)
    fixture.coordinator.focus(on: rowSet)
    fixture.coordinator.updateLoggedSet(squatSet, as: updatedLog)

    #expect(fixture.coordinator.expandedLoggedSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(fixture.coordinator.savedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
}

@MainActor
@Test func bindingNewSessionClearsSavedLoggedSetFeedback() throws {
    let fixture = try makeActionFixture()
    let squatSet = try #require(fixture.session.exercises.first { $0.order == 0 }?.sets.first)
    let updatedLog = SetLog(weight: .pounds(205), reps: 5, rpe: 8)
    let next = makeSingleSetSession(dayNumber: 2)

    fixture.coordinator.focus(on: squatSet)
    fixture.coordinator.updateLoggedSet(squatSet, as: updatedLog)
    fixture.coordinator.bind(to: next.session)

    #expect(fixture.coordinator.savedLoggedSetID == nil)
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
