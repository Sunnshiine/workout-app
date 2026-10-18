import Foundation
import Observation
import SwiftData
import Testing

@testable import WorkoutTracker

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
    var around: () -> [String] = { [] }
    private(set) var rowsAroundAnimation: [[String]] = []
    var reducesMotion: Bool { false }

    func animate(_ motion: SessionMotion, _ change: () throws -> Void) rethrows {
        rowsAroundAnimation.append(around())
        try change()
        rowsAroundAnimation.append(around())
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
private func makeLedgerCoordinator(
    session: Session,
    restTimer: RestTimer = RestTimer(
        clock: ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 0)),
        expiryScheduler: HeldRestExpiry()
    )
) -> (SessionCoordinator, SessionVerbLedger) {
    let ledger = SessionVerbLedger()
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: ledger,
            navigation: SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) }),
            sync: ledger,
            restTimer: restTimer,
            restDurations: restDurations(standard: 210),
            liveActivity: ledger,
            motion: ledger
        )
    )
    ledger.coordinator = coordinator
    return (coordinator, ledger)
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
            .liveActivityStarted,
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
@Test func aLiveEdgeLogThatEndsASupersetEndsItInsideTheInjectedAnimation() throws {
    let session = makePlannedPairingSession()
    connectCoordinatorWeek([session])
    let liveActivity = SpySessionLiveActivityAdapter()
    let motion = SampleAroundMotion()
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: SpySessionLoggingAdapter(),
            navigation: SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) }),
            sync: SpySessionSyncAdapter(),
            restTimer: RestTimer(clock: ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))),
            liveActivity: liveActivity,
            motion: motion
        )
    )
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let lastSquatSet = try #require(squat.sets.first)
    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))
    motion.around = { stageRowIDs(coordinator, in: session) }

    coordinator.log(lastSquatSet, as: SetLog(weight: .pounds(315), reps: 5, rpe: .seven))

    #expect(liveActivity.calls.count == 1)
    #expect(motion.rowsAroundAnimation == [["exercise-0", "superset-1"], ["exercise-0", "exercise-1", "exercise-2"]])
    #expect(coordinator.stage(in: session, lookup: .empty).queue.rows.map(\.kind) == [.pairableExercise, .exercise, .pairableExercise])
}
