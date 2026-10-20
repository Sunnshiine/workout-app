import Foundation
import Observation
import SwiftData
import Testing

@testable import WorkoutTracker

enum TestLoggingError: Error, Equatable {
    case failed
}

@MainActor
final class SpySessionLoggingAdapter: SessionLoggingAdapter {
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
final class SpySessionSyncAdapter: SessionSyncAdapter {
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
@Observable
final class SpySessionNavigationAdapter: SessionNavigationAdapter {
    var canMoveOn = false
    var openExercises: [Exercise] = []
    /// The Viewed Session's live edge, which the rest Live Activity is reconciled at.
    var liveEdge: LiveEdge = .browsedAway
    var liveEdgeOfSession: (Session) -> LiveEdge
    var readAtCelebrationRequest: () -> Bool = { false }
    var currentSession: Session?
    private(set) var celebrationRequests: [Bool] = []
    private(set) var shownAddresses: [SessionAddress] = []
    private(set) var currentSessionShows = 0

    init(liveEdge: @escaping (Session) -> LiveEdge = { _ in .browsedAway }) {
        self.liveEdgeOfSession = liveEdge
    }

    /// The live edge is `current`, as the store resolves it.
    convenience init(current: Session?) {
        self.init { session in
            guard let current, session === current else { return .browsedAway }
            return .atLiveEdge(currentSession: current)
        }
        currentSession = current
    }

    func showCurrent() {
        currentSessionShows += 1
    }

    func liveEdge(for session: Session) -> LiveEdge {
        liveEdgeOfSession(session)
    }

    func requestMoveOnCelebration() {
        celebrationRequests.append(readAtCelebrationRequest())
    }

    func show(_ address: SessionAddress) {
        shownAddresses.append(address)
    }
}

@MainActor
final class SpySessionLiveActivityAdapter: SessionLiveActivityAdapter {
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

/// A real `SettingsStore` holding these rest lengths, read at each rest's start.
@MainActor
func restDurations(
    standard: Int = RestDurationSetting.standard.seconds,
    superset: Int = RestDurationSetting.superset.seconds
) -> SettingsStore {
    let settings = SettingsStore(defaults: .inMemory())
    settings.setStandardRestDuration(RestDurationSetting(seconds: standard))
    settings.setSupersetRestDuration(RestDurationSetting(seconds: superset))
    return settings
}

@MainActor
final class ManualSessionTransitionClock: SessionTransitionClock {
    private(set) var sleptDurations: [Duration] = []
    private var sleepers: [CheckedContinuation<CheckedContinuation<Void, Never>, Never>] = []

    func sleep(for duration: Duration) async {
        sleptDurations.append(duration)
        let returnFromAdvanceAfterCallerRuns = await withCheckedContinuation { sleeper in
            sleepers.append(sleeper)
        }
        returnFromAdvanceAfterCallerRuns.resume()
    }

    func waitForSleep(sourceLocation: SourceLocation = #_sourceLocation) async {
        await waitUntil(
            { !sleptDurations.isEmpty },
            orRecord: "the coordinator never slept on the transition clock",
            sourceLocation: sourceLocation
        )
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
final class ManualCoordinatorRestClock: RestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

func makeCoordinatorSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)

    let completedSquat = Exercise(name: "Squat", coachNote: nil, order: 0)
    completedSquat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
    ]

    let bench = Exercise(name: "Bench Press", coachNote: nil, order: 1)
    let firstBenchSet = ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    let secondBenchSet = ExerciseSet(index: 1, prescribedReps: "6", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    bench.sets = [firstBenchSet, secondBenchSet]

    let row = Exercise(name: "DB Row", coachNote: nil, order: 2)
    row.sets = [
        ExerciseSet(index: 0, prescribedReps: "10", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    session.exercises = [row, bench, completedSquat]
    return placedInBlock(session)
}

func makePlannedPairingSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)

    let press = Exercise(name: "Press", coachNote: nil, order: 0)
    press.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let squat = Exercise(name: "Squat", coachNote: nil, order: 1)
    squat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let bench = Exercise(name: "Bench Press", coachNote: nil, order: 2)
    bench.sets = [
        ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    session.exercises = [bench, press, squat]
    return placedInBlock(session)
}

func makeSquatAndRDLSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)
    let squat = Exercise(name: "Back Squat", coachNote: nil, order: 0)
    let rdl = Exercise(name: "2-3:1:0 BB RDL", coachNote: nil, order: 1)
    for exercise in [squat, rdl] {
        exercise.sets = (0..<2).map {
            ExerciseSet(index: $0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
        }
    }
    session.exercises = [squat, rdl]
    return placedInBlock(session)
}

func makeFourExercisePairingSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)

    let press = Exercise(name: "Press", coachNote: nil, order: 0)
    press.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let squat = Exercise(name: "Squat", coachNote: nil, order: 1)
    squat.sets = [
        ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let bench = Exercise(name: "Bench Press", coachNote: nil, order: 2)
    bench.sets = [
        ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let row = Exercise(name: "DB Row", coachNote: nil, order: 3)
    row.sets = [
        ExerciseSet(index: 0, prescribedReps: "10", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    session.exercises = [row, bench, press, squat]
    return placedInBlock(session)
}

func makeSingleSetSession(dayNumber: Int) -> (session: Session, set: ExerciseSet) {
    let session = Session(dayNumber: dayNumber, date: nil)
    let exercise = Exercise(name: "Bench Press", coachNote: nil, order: 0)
    let set = ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    exercise.sets = [set]
    session.exercises = [exercise]
    return (placedInBlock(session), set)
}

@MainActor
func connectCoordinatorWeek(_ sessions: [Session]) {
    let week = Week(number: 1)
    week.sessions = sessions
    week.block = Block(tabName: "Block 27")
}

struct CoordinatorActionFixture {
    let session: Session
    let coordinator: SessionCoordinator
    let logging: SpySessionLoggingAdapter
    let sync: SpySessionSyncAdapter
}

struct CoordinatorRestActionFixture {
    let session: Session
    let coordinator: SessionCoordinator
    let restTimer: RestTimer
}

@MainActor
func stageRowIDs(_ coordinator: SessionCoordinator, in session: Session) -> [String] {
    coordinator.stage(in: session, lookup: .empty).queue.rows.map(\.id)
}

@MainActor
func exerciseStage(_ coordinator: SessionCoordinator, in session: Session) -> ExerciseStage? {
    guard case .exercise(let stage) = coordinator.stage(in: session, lookup: .empty).focus else { return nil }
    return stage
}

@MainActor
func supersetStage(_ coordinator: SessionCoordinator, in session: Session) -> SupersetStage? {
    guard case .superset(let stage) = coordinator.stage(in: session, lookup: .empty).focus else { return nil }
    return stage
}

@MainActor
func makeActionFixture() throws -> CoordinatorActionFixture {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(logging: logging, sync: sync),
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
func makeRestActionFixture(
    liveActivity: any SessionLiveActivityAdapter = InertSessionLiveActivity()
) throws -> CoordinatorRestActionFixture {
    let session = makeCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let clock = ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))
    let restTimer = RestTimer(clock: clock)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: logging,
            navigation: SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) }),
            sync: sync,
            restTimer: restTimer,
            liveActivity: liveActivity,
            motion: ImmediateSessionMotion()
        )
    )
    return CoordinatorRestActionFixture(
        session: session,
        coordinator: coordinator,
        restTimer: restTimer
    )
}
