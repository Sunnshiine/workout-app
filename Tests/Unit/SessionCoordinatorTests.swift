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
    var afterLogWrite: () -> Void = {}

    func log(_ set: ExerciseSet, as log: SetLog) throws {
        if let error { throw error }
        loggedSets.append((set, log))
        set.setLog = log
        set.state = .logged
        afterLogWrite()
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
private final class SpySessionNavigationAdapter: SessionNavigationAdapter {
    var canMoveOn = false
    var openExercises: [Exercise] = []
    var readAtCelebrationRequest: () -> Bool = { false }
    private(set) var celebrationRequests: [Bool] = []
    private(set) var shownAddresses: [SessionAddress] = []

    func requestMoveOnCelebration() {
        celebrationRequests.append(readAtCelebrationRequest())
    }

    func show(_ address: SessionAddress) {
        shownAddresses.append(address)
    }
}

@MainActor
private final class SpySessionLiveActivityAdapter: SessionLiveActivityAdapter {
    private(set) var calls: [(content: LiveActivityRestContent, sessionLabel: String)] = []
    private(set) var endCallCount = 0
    private(set) var invalidationCalls: [LiveEdge] = []

    func startOrUpdate(restContent: LiveActivityRestContent, sessionLabel: String) {
        calls.append((restContent, sessionLabel))
    }

    func end() {
        endCallCount += 1
    }

    func endIfInvalidated(at liveEdge: LiveEdge) {
        invalidationCalls.append(liveEdge)
    }
}

private enum SessionVerbEntry: Equatable {
    case began(SessionMotion, focus: ActiveSetID?)
    case logged
    case skipped
    case deleted
    case liveActivityStarted
    case liveActivityReconciled
    case ended(focus: ActiveSetID?)
    case flushRequested
    case failureReported
}

/// Samples a value just before and just after each transaction's change.
@MainActor
private final class SampleAroundMotion: SessionMotionPerforming {
    var around: () -> Int = { 0 }
    private(set) var firedAroundAnimation: [Int] = []
    var reducesMotion: Bool { false }

    func animate(_ motion: SessionMotion, _ change: () throws -> Void) rethrows {
        firedAroundAnimation.append(around())
        try change()
        firedAroundAnimation.append(around())
    }
}

@MainActor
private final class SessionVerbLedger: SessionMotionPerforming, SessionLoggingAdapter, SessionSyncAdapter, SessionLiveActivityAdapter {
    var reducesMotion = false
    var writeError: TestLoggingError?
    weak var coordinator: SessionCoordinator?
    private(set) var entries: [SessionVerbEntry] = []

    var motions: [SessionMotion] {
        entries.compactMap { entry in
            guard case .began(let motion, _) = entry else { return nil }
            return motion
        }
    }

    func animate(_ motion: SessionMotion, _ change: () throws -> Void) rethrows {
        entries.append(.began(motion, focus: coordinator?.activeSetID))
        defer { entries.append(.ended(focus: coordinator?.activeSetID)) }
        try change()
    }

    func log(_ set: ExerciseSet, as log: SetLog) throws {
        if let writeError { throw writeError }
        entries.append(.logged)
        set.setLog = log
        set.state = .logged
    }

    func skip(_ set: ExerciseSet) throws {
        entries.append(.skipped)
        set.setLog = nil
        set.state = .skipped
    }

    func deleteLog(for set: ExerciseSet) throws {
        entries.append(.deleted)
        set.setLog = nil
        set.state = .pending
    }

    func reportLocalWriteFailure(_ error: any Error) {
        entries.append(.failureReported)
    }

    func requestPendingWriteFlush() {
        entries.append(.flushRequested)
    }

    func startOrUpdate(restContent: LiveActivityRestContent, sessionLabel: String) {
        entries.append(.liveActivityStarted)
    }

    func end() {}

    func endIfInvalidated(at liveEdge: LiveEdge) {
        entries.append(.liveActivityReconciled)
    }
}

@MainActor
private func makeLedgerCoordinator(session: Session, restTimer: RestTimer? = nil) -> (SessionCoordinator, SessionVerbLedger) {
    let ledger = SessionVerbLedger()
    let coordinator = SessionCoordinator()
    coordinator.bind(
        to: session,
        logging: ledger,
        sync: ledger,
        restTimer: restTimer,
        standardRestDuration: { 210 },
        liveActivity: ledger,
        navigation: SpySessionNavigationAdapter(),
        motion: ledger,
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    ledger.coordinator = coordinator
    return (coordinator, ledger)
}

@MainActor
private final class ManualSessionTransitionClock: SessionTransitionClock {
    private(set) var sleptDurations: [Duration] = []
    private var sleepers: [CheckedContinuation<CheckedContinuation<Void, Never>, Never>] = []
    private var sleepWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async {
        sleptDurations.append(duration)
        let waiters = sleepWaiters
        sleepWaiters = []
        waiters.forEach { $0.resume() }

        let returnFromAdvanceAfterCallerRuns = await withCheckedContinuation { sleeper in
            sleepers.append(sleeper)
        }
        returnFromAdvanceAfterCallerRuns.resume()
    }

    func waitForSleep() async {
        if !sleptDurations.isEmpty { return }

        await withCheckedContinuation { continuation in
            sleepWaiters.append(continuation)
        }
    }

    func advance() async {
        let wokenSleepers = sleepers
        sleepers = []
        for sleeper in wokenSleepers {
            await withCheckedContinuation { returnFromAdvance in
                sleeper.resume(returning: returnFromAdvance)
            }
        }
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

private func makeSquatAndRDLSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)
    let squat = Exercise(name: "Back Squat", baseName: "Back Squat", cadence: nil, coachNote: nil, order: 0)
    let rdl = Exercise(name: "2-3:1:0 BB RDL", baseName: "BB RDL", cadence: "2-3:1:0", coachNote: nil, order: 1)
    for exercise in [squat, rdl] {
        exercise.sets = (0..<2).map {
            ExerciseSet(index: $0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
        }
    }
    session.exercises = [squat, rdl]
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
    let firstSquatSet = ExerciseSet(
        index: 0,
        prescribedReps: "5",
        prescribedLoad: "RPE 7",
        percentOneRM: nil,
        state: .pending
    )
    let secondSquatSet = ExerciseSet(
        index: 1,
        prescribedReps: "5",
        prescribedLoad: "RPE 8",
        percentOneRM: nil,
        state: .pending
    )
    squat.sets = [firstSquatSet, secondSquatSet]

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
}

private struct CoordinatorRestActionFixture {
    let session: Session
    let coordinator: SessionCoordinator
    let restTimer: RestTimer
}

@MainActor
private func stageRowIDs(_ coordinator: SessionCoordinator, in session: Session) -> [String] {
    coordinator.stage(in: session, lookup: .empty).queue.rows.map(\.id)
}

@MainActor
private func exerciseStage(_ coordinator: SessionCoordinator, in session: Session) -> ExerciseStage? {
    guard case .exercise(let stage) = coordinator.stage(in: session, lookup: .empty).focus else { return nil }
    return stage
}

@MainActor
private func supersetStage(_ coordinator: SessionCoordinator, in session: Session) -> SupersetStage? {
    guard case .superset(let stage) = coordinator.stage(in: session, lookup: .empty).focus else { return nil }
    return stage
}

@MainActor
private func makeActionFixture() throws -> CoordinatorActionFixture {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(
        session: session,
        logging: logging,
        sync: sync,
        transitionClock: ManualSessionTransitionClock()
    )
    return CoordinatorActionFixture(
        session: session,
        coordinator: coordinator,
        logging: logging,
        sync: sync
    )
}

@MainActor
private func makeRestActionFixture(
    liveActivity: (any SessionLiveActivityAdapter)? = nil
) throws -> CoordinatorRestActionFixture {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator()
    coordinator.bind(
        to: session,
        logging: logging,
        sync: sync,
        restTimer: restTimer,
        liveActivity: liveActivity,
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
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
@Test func theStageListsOrdinaryExercisesInSessionOrderWithTheirPairingRoles() throws {
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

    let stage = coordinator.stage(in: session, lookup: .empty)

    #expect(stage.queue.rows.map(\.id) == ["exercise-0", "exercise-1", "exercise-2"])
    #expect(stage.queue.rows.map(\.isOnStage) == [false, true, false])
    #expect(exerciseStage(coordinator, in: session)?.branch.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
    #expect(stage.queue.rows.map(\.pairingRole) == [.ineligibleTarget, .source, .confirmingTarget])
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

    let review = try #require(exerciseStage(coordinator, in: session))
    #expect(review.exercise === completedSquatSet.exercise)
    #expect(review.branch.activeSetID == nil)
    #expect(review.card?.id == "stage-review-0-0")

    coordinator.focus(on: completedSquatSet)

    #expect(coordinator.expandedLoggedSetID == nil)
    #expect(coordinator.visualFocusOwner == .activeSet(ActiveSetID(exerciseOrder: 1, setIndex: 0)))
    let active = try #require(exerciseStage(coordinator, in: session))
    #expect(active.branch.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(active.card?.id == "stage-active-1-0")
}

@MainActor
@Test func theStageFusesASupersetAtItsLowerOrderedSideInSessionOrder() throws {
    let session = makeFourExercisePairingSession()
    let coordinator = SessionCoordinator(session: session)
    let press = try #require(session.exercises.first { $0.order == 0 })
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let row = try #require(session.exercises.first { $0.order == 3 })

    #expect(coordinator.createSuperset(from: squat, to: row, in: session))

    let rows = coordinator.stage(in: session, lookup: .empty).queue.rows

    #expect(rows.map(\.id) == ["exercise-0", "superset-1", "exercise-2"])
    #expect(rows.map(\.title) == ["Press", "Squat + DB Row", "Bench Press"])
    #expect(rows.map(\.exercise) == [press, squat, bench])
    #expect(rows[1].sets == squat.sets + row.sets)
}

@MainActor
@Test func theStageCarriesTheLastPerformedLineFromTheLookupStore() throws {
    let container = try sessionCoordinatorContainer()
    let context = container.mainContext
    context.insert(
        LastPerformedEntry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "185x6@7",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "W3 D2"
        )
    )
    try context.save()
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session)

    let stage = coordinator.stage(in: session, lookup: LastPerformedLookupStore(context: context).snapshot)

    guard case .exercise(let bench) = stage.focus else {
        Issue.record("Expected Bench Press on stage")
        return
    }
    #expect(bench.exercise.order == 1)
    #expect(bench.lastPerformed?.resultText == "185x6@7")
    #expect(bench.lastPerformed?.sourceText == "W3 D2")
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
    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2"])
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
    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2"])

    await clock.waitForSleep()

    #expect(clock.sleptDurations == [.milliseconds(220)])
    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2"])

    await clock.advance()

    #expect(coordinator.pairingMode == .inactive)
    #expect(coordinator.activeSetID == initialActiveSetID)
    let rows = coordinator.stage(in: session, lookup: .empty).queue.rows
    #expect(rows.map(\.id) == ["exercise-0", "superset-1"])
    #expect(rows.map(\.title) == ["Press", "Squat + Bench Press"])
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
    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2", "exercise-3"])
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
}

@MainActor
@Test func coordinatorFocusesPairedExerciseNextPendingSet() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(session: session)
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })

    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))
    #expect(coordinator.focusNextSupersetSet(for: bench, in: session))

    let expectedSetID = ActiveSetID(exerciseOrder: 2, setIndex: 0)
    #expect(coordinator.activeSetID == expectedSetID)
}

@MainActor
@Test func coordinatorSupersetSideSwitchCuts() throws {
    let session = makePlannedPairingSession()
    let (coordinator, ledger) = makeLedgerCoordinator(session: session)
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })

    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))
    #expect(coordinator.focusNextSupersetSet(for: bench, in: session))

    let expectedSetID = ActiveSetID(exerciseOrder: 2, setIndex: 0)
    #expect(ledger.motions == [.cut])
    #expect(coordinator.activeSetID == expectedSetID)
}

@MainActor
@Test func coordinatorFailedSupersetSideSwitchKeepsTheFocus() throws {
    let session = makePlannedPairingSession()
    let (coordinator, ledger) = makeLedgerCoordinator(session: session)
    let press = try #require(session.exercises.first { $0.order == 0 })

    #expect(!coordinator.focusNextSupersetSet(for: press, in: session))

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
}

@MainActor
@Test func coordinatorMembershipAgreesForPlannedButNotYetActiveSuperset() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(session: session)
    let press = try #require(session.exercises.first { $0.order == 0 })
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })

    // Focus stays on the unpaired press; the Superset is planned but not yet active.
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))

    // The stage fuses the two paired Exercises and keeps the unpaired one on stage alone.
    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "superset-1"])
    #expect(exerciseStage(coordinator, in: session)?.exercise === press)

    // The domain-predicate membership answers must agree with that projection while the
    // Superset is planned but not yet active: the unpaired press is not a member, so it
    // resolves no focus target …
    #expect(!coordinator.focusNextSupersetSet(for: press, in: session))
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))

    // … while a paired side is a member and resolves its next Pending Set as the target.
    #expect(coordinator.focusNextSupersetSet(for: bench, in: session))
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
}

@MainActor
@Test func aSupersetLogKeepsThePairOnStageBeforeDuringAndAfterTheFocusMove() throws {
    let session = makeSquatAndRDLSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let rdl = try #require(session.exercises.first { $0.order == 1 })
    let logging = SpySessionLoggingAdapter()
    let coordinator = SessionCoordinator(session: session, logging: logging, sync: SpySessionSyncAdapter())
    #expect(coordinator.createSuperset(from: squat, to: rdl, in: session))
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    #expect(supersetStage(coordinator, in: session)?.card?.id == "superset-active-0-0")
    var focusInsideTheLog: ActiveSetID?
    var cardInsideTheLog: String?
    logging.afterLogWrite = {
        focusInsideTheLog = coordinator.activeSetID
        cardInsideTheLog = supersetStage(coordinator, in: session)?.card?.id
    }

    coordinator.log(firstSquatSet, as: SetLog(weight: .pounds(225), reps: 5, rpe: .seven))

    #expect(focusInsideTheLog == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(cardInsideTheLog == "superset-active-0-0")
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(supersetStage(coordinator, in: session)?.card?.id == "superset-active-1-0")
    #expect(stageRowIDs(coordinator, in: session) == ["superset-0"])
}

@MainActor
@Test func coordinatorPreservesCurrentSessionFlowThroughTheStage() throws {
    let session = makeIntegratedCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(session: session, logging: logging, sync: sync)
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let finalSquatSet = try #require(squat.sets.first { $0.index == 1 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let squatLog = SetLog(weight: .pounds(315), reps: 5, rpe: .seven)

    coordinator.log(firstSquatSet, as: squatLog)

    #expect(firstSquatSet.state == .logged)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
    #expect(sync.flushRequestCount == 1)

    coordinator.deleteLog(for: firstSquatSet)

    #expect(firstSquatSet.state == .pending)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))

    coordinator.log(firstSquatSet, as: squatLog)
    coordinator.skip(finalSquatSet)

    #expect(finalSquatSet.state == .skipped)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))

    #expect(coordinator.createSuperset(from: bench, to: row, in: session))

    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "superset-1", "exercise-3"])
    #expect(supersetStage(coordinator, in: session)?.branch.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))

    #expect(coordinator.focusNextSupersetSet(for: row, in: session))
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(supersetStage(coordinator, in: session)?.focused === row)

    coordinator.dismissSuperset(containing: row, in: session)

    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2", "exercise-3"])
    #expect(logging.loggedSets.map(\.set) == [firstSquatSet, firstSquatSet])
    #expect(logging.skippedSets == [finalSquatSet])
    #expect(logging.deletedSets == [firstSquatSet])
    #expect(sync.reportedErrors.isEmpty)
}

@MainActor
@Test func loggingSetUsesAdaptersAdvancesFocusAndFlushes() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)

    fixture.coordinator.log(firstBenchSet, as: log)

    #expect(fixture.logging.loggedSets.count == 1)
    #expect(fixture.logging.loggedSets.first?.set === firstBenchSet)
    #expect(fixture.logging.loggedSets.first?.log == log)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
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

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_210))
    #expect(restTimer.remaining == 210)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(restTimer.label == "Rest")
}

@MainActor
@Test func loggingSetInSupersetStartsConfiguredSupersetRestTimer() throws {
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
        standardRestDuration: { 210 },
        supersetRestDuration: { 45 }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    #expect(coordinator.createSuperset(from: bench, to: row, in: session))

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_045))
    #expect(restTimer.remaining == 45)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(restTimer.label == "Superset rest")
}

@MainActor
@Test func loggingEachSupersetSetRestartsSupersetRestTimer() throws {
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
        standardRestDuration: { 210 },
        supersetRestDuration: { 45 }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let rowSet = try #require(row.sets.first)

    #expect(coordinator.createSuperset(from: bench, to: row, in: session))

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    clock.now.addTimeInterval(10)
    coordinator.log(rowSet, as: SetLog(weight: .pounds(95), reps: 10, rpe: .seven))

    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_055))
    #expect(restTimer.remaining == 45)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(restTimer.restartRevision == 2)
    #expect(restTimer.label == "Superset rest")
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

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    clock.now.addTimeInterval(60)
    coordinator.log(rowSet, as: SetLog(weight: .pounds(95), reps: 10, rpe: .seven))

    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_270))
    #expect(restTimer.remaining == 210)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(restTimer.restartRevision == 2)
}

@MainActor
@Test func loggingCurrentSessionSetStartsLiveActivityFromRestContent() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let liveActivity = SpySessionLiveActivityAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator()
    coordinator.bind(
        to: session,
        logging: logging,
        sync: sync,
        restTimer: restTimer,
        standardRestDuration: { 210 },
        liveActivity: liveActivity,
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    let call = try #require(liveActivity.calls.first)
    #expect(liveActivity.calls.count == 1)
    #expect(liveActivity.invalidationCalls.count == 1)
    #expect(call.sessionLabel == "Week 1 - Day 1")
    #expect(call.content.exerciseName == "Bench Press")
    #expect(call.content.prescribedReps == "6")
    #expect(call.content.prescribedLoad == "RPE 8")
    #expect(call.content.setsDone == 1)
    #expect(call.content.setsTotal == 2)
    #expect(call.content.restStartDate == Date(timeIntervalSinceReferenceDate: 2_000))
    #expect(call.content.restEndDate == Date(timeIntervalSinceReferenceDate: 2_210))
}

@MainActor
@Test func loggingAnotherCurrentSessionSetRequestsLiveActivityStartOrUpdateAgain() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let liveActivity = SpySessionLiveActivityAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator()
    coordinator.bind(
        to: session,
        logging: logging,
        sync: sync,
        restTimer: restTimer,
        standardRestDuration: { 210 },
        liveActivity: liveActivity,
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let secondBenchSet = try #require(bench.sets.first { $0.index == 1 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    clock.now.addTimeInterval(60)
    coordinator.log(secondBenchSet, as: SetLog(weight: .pounds(195), reps: 6, rpe: .eight))

    #expect(liveActivity.calls.count == 2)
    #expect(liveActivity.invalidationCalls.count == 2)
    #expect(liveActivity.calls[1].content.exerciseName == "DB Row")
    #expect(liveActivity.calls[1].content.restStartDate == Date(timeIntervalSinceReferenceDate: 2_060))
    #expect(liveActivity.calls[1].content.restEndDate == Date(timeIntervalSinceReferenceDate: 2_270))
}

@MainActor
@Test func failedSetLogDoesNotStartLiveActivity() throws {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    logging.error = .failed
    let sync = SpySessionSyncAdapter()
    let liveActivity = SpySessionLiveActivityAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator()
    coordinator.bind(
        to: session,
        logging: logging,
        sync: sync,
        restTimer: restTimer,
        standardRestDuration: { 210 },
        liveActivity: liveActivity,
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(liveActivity.calls.isEmpty)
}

@MainActor
@Test func loggingSetFromNonCurrentSessionDoesNotStartLiveActivity() throws {
    let current = makeSingleSetSession(dayNumber: 1)
    let browsed = makeCoordinatorSession()
    browsed.dayNumber = 2
    connectCoordinatorWeek([current.session, browsed])
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let liveActivity = SpySessionLiveActivityAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator()
    coordinator.bind(
        to: browsed,
        logging: logging,
        sync: sync,
        restTimer: restTimer,
        standardRestDuration: { 210 },
        liveActivity: liveActivity,
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { LiveEdge.resolve(viewedSession: $0, currentSession: current.session) }
    )
    let bench = try #require(browsed.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(liveActivity.calls.isEmpty)
}

@MainActor
@Test func editSkipAndDeleteDoNotStartLiveActivity() throws {
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)

    let editLiveActivity = SpySessionLiveActivityAdapter()
    let editFixture = try makeRestActionFixture(liveActivity: editLiveActivity)
    let squatSet = try #require(editFixture.session.exercises.first { $0.order == 0 }?.sets.first)
    editFixture.coordinator.updateLoggedSet(squatSet, as: log)
    #expect(editLiveActivity.calls.isEmpty)
    #expect(editLiveActivity.invalidationCalls.count == 1)

    let skipLiveActivity = SpySessionLiveActivityAdapter()
    let skipFixture = try makeRestActionFixture(liveActivity: skipLiveActivity)
    let skipSet = try #require(skipFixture.session.exercises.first { $0.order == 1 }?.sets.first)
    skipFixture.coordinator.skip(skipSet)
    #expect(skipLiveActivity.calls.isEmpty)
    #expect(skipLiveActivity.invalidationCalls.count == 1)

    let deleteLiveActivity = SpySessionLiveActivityAdapter()
    let deleteFixture = try makeRestActionFixture(liveActivity: deleteLiveActivity)
    let deleteSet = try #require(deleteFixture.session.exercises.first { $0.order == 1 }?.sets.first)
    deleteSet.state = .logged
    deleteSet.setLog = log
    deleteFixture.coordinator.deleteLog(for: deleteSet)
    #expect(deleteLiveActivity.calls.isEmpty)
    #expect(deleteLiveActivity.invalidationCalls.count == 1)
}

@MainActor
@Test func deletingOriginSetCancelsRunningRestTimer() throws {
    let fixture = try makeRestActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let secondBenchSet = try #require(bench.sets.first { $0.index == 1 })

    fixture.coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    fixture.coordinator.deleteLog(for: secondBenchSet)

    #expect(fixture.restTimer.isRunning)

    fixture.coordinator.deleteLog(for: firstBenchSet)

    #expect(fixture.restTimer.interval == nil)
    #expect(fixture.restTimer.origin == nil)
    #expect(!fixture.restTimer.isRunning)
}

@MainActor
@Test func deletingMatchingSetInDifferentSessionDoesNotCancelRunningRestTimer() {
    let current = makeSingleSetSession(dayNumber: 1)
    let other = makeSingleSetSession(dayNumber: 2)
    connectCoordinatorWeek([current.session, other.session])
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

    coordinator.log(current.set, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    #expect(restTimer.isRunning)

    other.set.state = .logged
    other.set.setLog = SetLog(weight: .pounds(95), reps: 10, rpe: .seven)
    coordinator.deleteLog(for: other.set)

    #expect(restTimer.isRunning)
    #expect(restTimer.origin == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_210))
}

@MainActor
@Test func cancellingSessionRestForMoveOnDismissesRunningRestTimer() throws {
    let liveActivity = SpySessionLiveActivityAdapter()
    let fixture = try makeRestActionFixture(liveActivity: liveActivity)
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    fixture.coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    fixture.coordinator.cancelRestForSessionExit()

    #expect(fixture.restTimer.interval == nil)
    #expect(fixture.restTimer.origin == nil)
    #expect(!fixture.restTimer.isRunning)
    #expect(liveActivity.endCallCount == 1)
}

@MainActor
@Test func moveOnEndsTheRestBeforeItAsksForTheCelebration() throws {
    let session = makeCoordinatorSession()
    let restTimer = RestTimer(clock: ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000)))
    let liveActivity = SpySessionLiveActivityAdapter()
    let navigation = SpySessionNavigationAdapter()
    navigation.readAtCelebrationRequest = { restTimer.isRunning }
    let coordinator = SessionCoordinator()
    coordinator.bind(
        to: session,
        logging: SpySessionLoggingAdapter(),
        sync: SpySessionSyncAdapter(),
        restTimer: restTimer,
        liveActivity: liveActivity,
        navigation: navigation,
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let firstBenchSet = try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    #expect(restTimer.isRunning)

    coordinator.moveOn()

    #expect(navigation.celebrationRequests == [false])
    #expect(liveActivity.endCallCount == 1)
}

@MainActor
@Test func showingAnOpenExercisesSessionCancelsPairingAndShowsItsAddress() throws {
    let session = makeCoordinatorSession()
    let earlier = Session(dayNumber: 1, date: nil)
    let makeup = Exercise(name: "Front Squat", baseName: "Front Squat", cadence: nil, coachNote: nil, order: 0)
    earlier.exercises = [makeup]
    connectCoordinatorWeek([earlier, session])
    let navigation = SpySessionNavigationAdapter()
    let coordinator = SessionCoordinator(session: session, navigation: navigation)
    let bench = try #require(session.exercises.first { $0.order == 1 })
    #expect(coordinator.beginPairing(from: bench, in: session))

    coordinator.showSourceSession(of: makeup)

    #expect(coordinator.pairingMode == .inactive)
    #expect(navigation.shownAddresses == [SessionAddress(week: 1, day: 1)])
}

@MainActor
@Test func theStageOffersMoveOnAndOpenExercisesOnlyAtTheLiveEdge() throws {
    let session = makeCoordinatorSession()
    let makeup = Exercise(name: "Front Squat", baseName: "Front Squat", cadence: nil, coachNote: nil, order: 0)
    let navigation = SpySessionNavigationAdapter()
    navigation.canMoveOn = true
    navigation.openExercises = [makeup]
    var isAtLiveEdge = true
    let coordinator = SessionCoordinator()
    coordinator.bind(
        to: session,
        logging: SpySessionLoggingAdapter(),
        sync: SpySessionSyncAdapter(),
        navigation: navigation,
        motion: ImmediateSessionMotion(),
        liveEdge: { isAtLiveEdge ? .atLiveEdge(currentSession: $0) : .browsedAway }
    )

    let atLiveEdge = coordinator.stage(in: session, lookup: .empty).queue
    isAtLiveEdge = false
    let browsedAway = coordinator.stage(in: session, lookup: .empty).queue

    #expect(atLiveEdge.showsMoveOn)
    #expect(atLiveEdge.openExercises == [makeup])
    #expect(!browsedAway.showsMoveOn)
    #expect(browsedAway.openExercises.isEmpty)
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

    coordinator.log(current.set, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.interval == nil)
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

    coordinator.log(current.set, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_210))
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

    #expect(restTimer.interval == nil)
    #expect(logging.loggedSets.isEmpty)
    #expect(sync.flushRequestCount == 0)
}

@MainActor
@Test func editSkipAndDeleteDoNotStartRestTimer() throws {
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)

    let editFixture = try makeRestActionFixture()
    let squatSet = try #require(editFixture.session.exercises.first { $0.order == 0 }?.sets.first)
    editFixture.coordinator.updateLoggedSet(squatSet, as: log)
    #expect(editFixture.restTimer.interval == nil)

    let skipFixture = try makeRestActionFixture()
    let skipSet = try #require(skipFixture.session.exercises.first { $0.order == 1 }?.sets.first)
    skipFixture.coordinator.skip(skipSet)
    #expect(skipFixture.restTimer.interval == nil)

    let deleteFixture = try makeRestActionFixture()
    let deleteSet = try #require(deleteFixture.session.exercises.first { $0.order == 1 }?.sets.first)
    deleteSet.state = .logged
    deleteSet.setLog = log
    deleteFixture.coordinator.deleteLog(for: deleteSet)
    #expect(deleteFixture.restTimer.interval == nil)
}

@MainActor
@Test func updatingLoggedSetUsesAdaptersWithoutAdvancingActivePendingSet() throws {
    let fixture = try makeActionFixture()
    let squatSet = try #require(fixture.session.exercises.first { $0.order == 0 }?.sets.first)
    let updatedLog = SetLog(weight: .pounds(205), reps: 5, rpe: .eight)

    fixture.coordinator.focus(on: squatSet)
    fixture.coordinator.updateLoggedSet(squatSet, as: updatedLog)

    #expect(fixture.logging.loggedSets.count == 1)
    #expect(fixture.logging.loggedSets.first?.set === squatSet)
    #expect(fixture.logging.loggedSets.first?.log == updatedLog)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(fixture.coordinator.expandedLoggedSetID == nil)
    #expect(fixture.coordinator.visualFocusOwner == .activeSet(ActiveSetID(exerciseOrder: 1, setIndex: 0)))
    #expect(fixture.coordinator.savedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(fixture.sync.flushRequestCount == 1)
    #expect(fixture.sync.reportedErrors.isEmpty)
}

@MainActor
@Test func openingTheReviewOfASetJustLoggedRendersItExpanded() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    fixture.coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    fixture.coordinator.focus(on: firstBenchSet)

    #expect(fixture.coordinator.visualFocusOwner == .loggedSetReview(ActiveSetID(exerciseOrder: 1, setIndex: 0)))
    let card = try #require(exerciseStage(fixture.coordinator, in: fixture.session)?.card)
    #expect(card.id == "stage-review-1-0")
    #expect(card.mode == .reviewingLogged(showsSavedConfirmation: false))
}

@MainActor
@Test func pendingFocusMorphsForEachRetarget() throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger) = makeLedgerCoordinator(session: session)
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let secondBenchSet = try #require(bench.sets.first { $0.index == 1 })
    let rowSet = try #require(session.exercises.first { $0.order == 2 }?.sets.first)

    coordinator.focus(on: rowSet)
    coordinator.focus(on: secondBenchSet)
    coordinator.focus(on: firstBenchSet)

    #expect(ledger.motions == [.focusMorph, .focusMorph, .focusMorph])
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func updatingPreviousLoggedSetDoesNotCollapseNewlyExpandedLoggedSet() throws {
    let fixture = try makeActionFixture()
    let squatSet = try #require(fixture.session.exercises.first { $0.order == 0 }?.sets.first)
    let rowSet = try #require(fixture.session.exercises.first { $0.order == 2 }?.sets.first)
    rowSet.state = .logged
    let updatedLog = SetLog(weight: .pounds(205), reps: 5, rpe: .eight)

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
    let updatedLog = SetLog(weight: .pounds(205), reps: 5, rpe: .eight)
    let next = makeSingleSetSession(dayNumber: 2)

    fixture.coordinator.focus(on: squatSet)
    fixture.coordinator.updateLoggedSet(squatSet, as: updatedLog)
    fixture.coordinator.bind(to: next.session)

    #expect(fixture.coordinator.savedLoggedSetID == nil)
}

@MainActor
@Test func skippingSetUsesAdaptersAdvancesFocusAndFlushes() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })

    fixture.coordinator.skip(firstBenchSet)

    #expect(fixture.logging.skippedSets.count == 1)
    #expect(fixture.logging.skippedSets.first === firstBenchSet)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
    #expect(fixture.sync.flushRequestCount == 1)
    #expect(fixture.sync.reportedErrors.isEmpty)
}

@MainActor
@Test func deletingSetLogUsesAdaptersFocusesDeletedSetAndFlushes() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)
    fixture.coordinator.log(firstBenchSet, as: log)

    fixture.coordinator.deleteLog(for: firstBenchSet)

    #expect(fixture.logging.deletedSets.count == 1)
    #expect(fixture.logging.deletedSets.first === firstBenchSet)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(fixture.sync.flushRequestCount == 2)
    #expect(fixture.sync.reportedErrors.isEmpty)
}

@MainActor
@Test func loggingAdapterErrorReportsFailureWithoutAdvancingFocusOrFlushing() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)
    fixture.logging.error = .failed

    fixture.coordinator.log(firstBenchSet, as: log)

    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
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
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)

    coordinator.log(new.set, as: log)

    #expect(coordinator.session === new.session)
    #expect(logging.loggedSets.first?.set === new.set)
    #expect(new.set.state == .logged)
    #expect(old.set.state == .pending)
    #expect(coordinator.activeSetID == nil)
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
    new.set.setLog = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)

    coordinator.deleteLog(for: new.set)

    #expect(coordinator.session === new.session)
    #expect(logging.deletedSets.first === new.set)
    #expect(new.set.state == .pending)
    #expect(old.set.state == .pending)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(sync.flushRequestCount == 1)
}

@MainActor
@Test func sessionScreenWiringSendsLogToTheBoundAdaptersAndRequestsFlush() throws {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator()

    coordinator.bind(
        to: session,
        logging: logging,
        sync: sync,
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
    #expect(logging.loggedSets.count == 1)
    #expect(logging.loggedSets.first?.log == SetLog(weight: .pounds(185), reps: 6, rpe: .seven))
    #expect(sync.flushRequestCount == 1)
    #expect(sync.reportedErrors.isEmpty)
}

@MainActor
@Test func sessionScreenWiringStartsBoundRestTimerWithTheBoundDurations() throws {
    let session = makeCoordinatorSession()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let coordinator = SessionCoordinator()

    coordinator.bind(
        to: session,
        logging: SpySessionLoggingAdapter(),
        sync: SpySessionSyncAdapter(),
        restTimer: restTimer,
        standardRestDuration: { 123 },
        supersetRestDuration: { 77 },
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.remaining == 123)
    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_123))
    #expect(restTimer.label == "Rest")
}

@MainActor
@Test func sessionScreenWiringStartsBoundSupersetRestDurationForASupersetMember() throws {
    let session = makeCoordinatorSession()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let coordinator = SessionCoordinator()

    coordinator.bind(
        to: session,
        logging: SpySessionLoggingAdapter(),
        sync: SpySessionSyncAdapter(),
        restTimer: restTimer,
        standardRestDuration: { 123 },
        supersetRestDuration: { 77 },
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    #expect(coordinator.createSuperset(from: bench, to: row, in: session))

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.remaining == 77)
    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_077))
    #expect(restTimer.label == "Superset rest")
}

@MainActor
@Test func sessionScreenWiringDrivesTheBoundLiveActivityAdapter() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let configured = SpySessionLiveActivityAdapter()
    let bound = SpySessionLiveActivityAdapter()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let coordinator = SessionCoordinator(liveActivity: configured)

    coordinator.bind(
        to: session,
        logging: SpySessionLoggingAdapter(),
        sync: SpySessionSyncAdapter(),
        restTimer: restTimer,
        standardRestDuration: { 123 },
        liveActivity: bound,
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(configured.calls.isEmpty)
    #expect(configured.invalidationCalls.isEmpty)
    #expect(bound.calls.count == 1)
    #expect(bound.calls.first?.sessionLabel == "Week 1 - Day 1")
    #expect(bound.calls.first?.content.exerciseName == "Bench Press")
    #expect(bound.invalidationCalls.count == 1)
}

@MainActor
@Test func sessionScreenWiringKeepsTheConfiguredLiveActivityAdapterWhenNoneIsBound() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let configured = SpySessionLiveActivityAdapter()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let coordinator = SessionCoordinator(liveActivity: configured)

    coordinator.bind(
        to: session,
        logging: SpySessionLoggingAdapter(),
        sync: SpySessionSyncAdapter(),
        restTimer: restTimer,
        standardRestDuration: { 123 },
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(configured.calls.count == 1)
    #expect(configured.calls.first?.sessionLabel == "Week 1 - Day 1")
    #expect(configured.invalidationCalls.count == 1)
}

@MainActor
@Test func loggingAtTheLiveEdgeKeepsTheRestLiveActivityAlive() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let liveActivity = SpySessionLiveActivityAdapter()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let coordinator = SessionCoordinator(liveActivity: liveActivity)

    coordinator.bind(
        to: session,
        logging: SpySessionLoggingAdapter(),
        sync: SpySessionSyncAdapter(),
        restTimer: restTimer,
        standardRestDuration: { 123 },
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(liveActivity.calls.count == 1)
    #expect(liveActivity.invalidationCalls.map(\.isAtLiveEdge) == [true])
}

@MainActor
@Test func loggingWhileBrowsingAwayAsksTheRestLiveActivityToEnd() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let liveActivity = SpySessionLiveActivityAdapter()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let coordinator = SessionCoordinator(liveActivity: liveActivity)

    coordinator.bind(
        to: session,
        logging: SpySessionLoggingAdapter(),
        sync: SpySessionSyncAdapter(),
        restTimer: restTimer,
        standardRestDuration: { 123 },
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { _ in .browsedAway }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(liveActivity.calls.isEmpty)
    #expect(liveActivity.invalidationCalls == [.browsedAway])
}

@MainActor
@Test func sessionScreenWiringFallsBackToTheStandardAndSupersetRestDefaults() throws {
    let session = makeCoordinatorSession()
    let restClock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: restClock)
    let coordinator = SessionCoordinator()

    coordinator.bind(
        to: session,
        logging: SpySessionLoggingAdapter(),
        sync: SpySessionSyncAdapter(),
        restTimer: restTimer,
        navigation: SpySessionNavigationAdapter(),
        motion: ImmediateSessionMotion(),
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(restTimer.remaining == 120)

    #expect(coordinator.createSuperset(from: bench, to: row, in: session))
    let secondBenchSet = try #require(bench.sets.first { $0.index == 1 })
    coordinator.log(secondBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .eight))

    #expect(restTimer.remaining == 30)
}

@MainActor
@Test func readingTheStageWritesNoObservedState() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(session: session)
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))
    for set in squat.sets {
        set.state = .logged
    }
    let changes = ObservedChanges()
    changes.watch { _ = coordinator.canPair(bench, in: session) }

    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2"])

    #expect(changes.fired == 0)
}

@MainActor
@Test func aSideSwitchALogASkipAndATapEachMoveTheFocusInsideTheirMotion() throws {
    let session = makeSquatAndRDLSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let rdl = try #require(session.exercises.first { $0.order == 1 })
    let (coordinator, ledger) = makeLedgerCoordinator(session: session)
    #expect(coordinator.createSuperset(from: squat, to: rdl, in: session))
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let secondSquatSet = try #require(squat.sets.first { $0.index == 1 })
    let firstRDLSet = try #require(rdl.sets.first { $0.index == 0 })

    #expect(coordinator.focusNextSupersetSet(for: rdl, in: session))
    coordinator.log(firstRDLSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: .seven))
    coordinator.skip(firstSquatSet)
    coordinator.focus(on: secondSquatSet)

    #expect(
        ledger.entries == [
            .began(.cut, focus: ActiveSetID(exerciseOrder: 0, setIndex: 0)),
            .ended(focus: ActiveSetID(exerciseOrder: 1, setIndex: 0)),
            .began(.momentumFlow, focus: ActiveSetID(exerciseOrder: 1, setIndex: 0)),
            .logged,
            .liveActivityReconciled,
            .ended(focus: ActiveSetID(exerciseOrder: 0, setIndex: 0)),
            .flushRequested,
            .began(.skipFadeUp, focus: ActiveSetID(exerciseOrder: 0, setIndex: 0)),
            .skipped,
            .liveActivityReconciled,
            .ended(focus: ActiveSetID(exerciseOrder: 1, setIndex: 1)),
            .flushRequested,
            .began(.focusMorph, focus: ActiveSetID(exerciseOrder: 1, setIndex: 1)),
            .ended(focus: ActiveSetID(exerciseOrder: 0, setIndex: 1))
        ]
    )
}

@MainActor
@Test func aLogWritesStartsRestAndAdvancesInsideOneMomentumFlowAndRequestsTheFlushAfter() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let restTimer = RestTimer(clock: ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000)))
    let (coordinator, ledger) = makeLedgerCoordinator(session: session, restTimer: restTimer)
    let firstBenchSet = try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 0 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(
        ledger.entries == [
            .began(.momentumFlow, focus: ActiveSetID(exerciseOrder: 1, setIndex: 0)),
            .logged,
            .liveActivityStarted,
            .liveActivityReconciled,
            .ended(focus: ActiveSetID(exerciseOrder: 1, setIndex: 1)),
            .flushRequested
        ]
    )
    #expect(restTimer.interval?.end == Date(timeIntervalSinceReferenceDate: 2_210))
}

@MainActor
@Test func aLogWhoseWriteFailsStartsNoRestOrLiveActivityKeepsFocusAndRequestsNoFlush() throws {
    let session = makeCoordinatorSession()
    connectCoordinatorWeek([session])
    let restTimer = RestTimer(clock: ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000)))
    let (coordinator, ledger) = makeLedgerCoordinator(session: session, restTimer: restTimer)
    ledger.writeError = .failed
    let firstBenchSet = try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 0 })

    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(
        ledger.entries == [
            .began(.momentumFlow, focus: ActiveSetID(exerciseOrder: 1, setIndex: 0)),
            .ended(focus: ActiveSetID(exerciseOrder: 1, setIndex: 0)),
            .failureReported
        ]
    )
    #expect(restTimer.interval == nil)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func aSkipWritesAndAdvancesInsideOneSkipFadeUp() throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger) = makeLedgerCoordinator(session: session)
    let firstBenchSet = try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 0 })

    coordinator.skip(firstBenchSet)

    #expect(
        ledger.entries == [
            .began(.skipFadeUp, focus: ActiveSetID(exerciseOrder: 1, setIndex: 0)),
            .skipped,
            .liveActivityReconciled,
            .ended(focus: ActiveSetID(exerciseOrder: 1, setIndex: 1)),
            .flushRequested
        ]
    )
}

@MainActor
@Test func deletingOrCorrectingALogRunsNoMotion() throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger) = makeLedgerCoordinator(session: session)
    let squatSet = try #require(session.exercises.first { $0.order == 0 }?.sets.first)

    coordinator.updateLoggedSet(squatSet, as: SetLog(weight: .pounds(315), reps: 5, rpe: .seven))
    coordinator.deleteLog(for: squatSet)

    #expect(
        ledger.entries == [
            .logged,
            .liveActivityReconciled,
            .flushRequested,
            .deleted,
            .liveActivityReconciled,
            .flushRequested
        ]
    )
}

@MainActor
@Test func focusingMorphsExceptToCollapseAReviewOrLandOnASkippedSetAndYieldsToReduceMotion() throws {
    let session = makeCoordinatorSession()
    let (coordinator, ledger) = makeLedgerCoordinator(session: session)
    let squatSet = try #require(session.exercises.first { $0.order == 0 }?.sets.first)
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let secondBenchSet = try #require(bench.sets.first { $0.index == 1 })
    let rowSet = try #require(session.exercises.first { $0.order == 2 }?.sets.first)
    rowSet.state = .skipped

    let motionPerFocus = [secondBenchSet, squatSet, squatSet, rowSet].map { set in
        let motionsBefore = ledger.motions.count
        coordinator.focus(on: set)
        return ledger.motions.dropFirst(motionsBefore).first
    }
    #expect(motionPerFocus == [.focusMorph, .focusMorph, nil, nil])

    ledger.reducesMotion = true
    coordinator.focus(on: squatSet)
    #expect(coordinator.expandedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    coordinator.log(firstBenchSet, as: SetLog(weight: .pounds(185), reps: 6, rpe: .seven))

    #expect(ledger.motions == [.focusMorph, .focusMorph, .momentumFlow])
}

@MainActor
@Test func aSupersetEndedByLoggingOneSidesLastSetStaysEndedWhenThatLogIsDeleted() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(session: session, logging: SpySessionLoggingAdapter(), sync: SpySessionSyncAdapter())
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let lastSquatSet = try #require(squat.sets.first)
    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))

    coordinator.log(lastSquatSet, as: SetLog(weight: .pounds(315), reps: 5, rpe: .seven))
    coordinator.deleteLog(for: lastSquatSet)

    #expect(lastSquatSet.state == .pending)
    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2"])
    #expect(coordinator.canPair(squat, in: session))
}

@MainActor
@Test func aLiveEdgeLogThatEndsASupersetEndsItInsideTheInjectedAnimation() throws {
    let session = makePlannedPairingSession()
    connectCoordinatorWeek([session])
    let liveActivity = SpySessionLiveActivityAdapter()
    let motion = SampleAroundMotion()
    let coordinator = SessionCoordinator()
    coordinator.bind(
        to: session,
        logging: SpySessionLoggingAdapter(),
        sync: SpySessionSyncAdapter(),
        restTimer: RestTimer(clock: ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))),
        liveActivity: liveActivity,
        navigation: SpySessionNavigationAdapter(),
        motion: motion,
        liveEdge: { .atLiveEdge(currentSession: $0) }
    )
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let lastSquatSet = try #require(squat.sets.first)
    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))
    let changes = ObservedChanges()
    changes.watch { _ = coordinator.canPair(bench, in: session) }
    motion.around = { changes.fired }

    coordinator.log(lastSquatSet, as: SetLog(weight: .pounds(315), reps: 5, rpe: .seven))

    #expect(liveActivity.calls.count == 1)
    #expect(motion.firedAroundAnimation == [0, 1])
    #expect(coordinator.canPair(bench, in: session))
}

@MainActor
@Test func loggingASetOutsideEverySupersetNotifiesNoPairingReader() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(session: session, logging: SpySessionLoggingAdapter(), sync: SpySessionSyncAdapter())
    let press = try #require(session.exercises.first { $0.order == 0 })
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let pressSet = try #require(press.sets.first)
    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))
    let changes = ObservedChanges()
    changes.watch { _ = coordinator.canPair(bench, in: session) }

    coordinator.log(pressSet, as: SetLog(weight: .pounds(135), reps: 5, rpe: .seven))

    #expect(pressSet.state == .logged)
    #expect(changes.fired == 0)
}

@MainActor
@Test func rebindingAfterASupersetLogKeepsTheFocusOnThePartner() throws {
    let session = makeSquatAndRDLSession()
    let press = Exercise(name: "Press", baseName: "Press", cadence: nil, coachNote: nil, order: 2)
    press.sets = [ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)]
    session.exercises.append(press)
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let rdl = try #require(session.exercises.first { $0.order == 1 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let pressSet = try #require(press.sets.first)
    let coordinator = SessionCoordinator(session: session, logging: SpySessionLoggingAdapter(), sync: SpySessionSyncAdapter())
    coordinator.focus(on: pressSet)
    #expect(coordinator.createSuperset(from: squat, to: rdl, in: session))
    coordinator.log(firstSquatSet, as: SetLog(weight: .pounds(225), reps: 5, rpe: .seven))

    coordinator.bind(to: session)

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}
