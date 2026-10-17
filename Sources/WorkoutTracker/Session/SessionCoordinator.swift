import Foundation
import Observation

@MainActor
protocol SessionTransitionClock {
    func sleep(for duration: Duration) async
}

enum SessionCoordinatorError: Error {
    case missingSession
}

private struct TaskSessionTransitionClock: SessionTransitionClock {
    func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}

@MainActor
@Observable
final class SessionCoordinator {
    private(set) var session: Session?
    private(set) var savedLoggedSetID: ActiveSetID?

    @ObservationIgnored private let focusManager: ActiveSetFocusManager
    @ObservationIgnored private let pairing: SupersetPairing
    @ObservationIgnored private let wiring: SessionWiring

    init(
        session: Session? = nil,
        wiring: SessionWiring,
        transitionClock: any SessionTransitionClock = TaskSessionTransitionClock()
    ) {
        self.session = session
        self.wiring = wiring
        let focusManager = ActiveSetFocusManager(session: session)
        self.focusManager = focusManager
        self.pairing = SupersetPairing(focusManager: focusManager, clock: transitionClock)
    }

    var activeSetID: ActiveSetID? { focusManager.activeSetID }
    var restTimer: RestTimer { wiring.restTimer }
    var expandedLoggedSetID: ActiveSetID? { focusManager.expandedLoggedSetID }
    var pairingMode: PairingMode { pairing.mode }

    func bind(to session: Session?) {
        self.session = session
        savedLoggedSetID = nil
        cancelPairing()
        focusManager.reset(to: session)
    }

    func advanceAfterLog(_ set: ExerciseSet, in session: Session) {
        focusManager.advanceAfterLog(set, in: session)
    }

    func advanceAfterSkip(_ set: ExerciseSet, in session: Session) {
        focusManager.advanceAfterSkip(set, in: session)
    }

    func focus(on set: ExerciseSet) {
        perform(focusManager.motion(forFocusing: set)) {
            focusManager.focus(on: set)
        }
    }

    func log(_ set: ExerciseSet, as log: SetLog) {
        do {
            let session = try actionSession(for: set)
            let wasSupersetMember = isSupersetMember(set)
            try perform(.momentumFlow) {
                try wiring.logging.log(set, as: log)
                startRest(afterLogging: set, in: session, wasSupersetMember: wasSupersetMember)
                reconcileLiveActivity(for: session)
                advanceAfterLog(set, in: session)
            }
            wiring.sync.requestPendingWriteFlush()
        } catch {
            wiring.sync.reportLocalWriteFailure(error)
        }
    }

    func log(_ setLog: SetLog, for slot: SetCardSlot) {
        switch slot.mode {
        case .logging:
            log(slot.set, as: setLog)
        case .reviewingLogged:
            updateLoggedSet(slot.set, as: setLog)
        }
    }

    func skip(_ set: ExerciseSet) {
        do {
            let session = try actionSession(for: set)
            try perform(.skipFadeUp) {
                try wiring.logging.skip(set)
                reconcileLiveActivity(for: session)
                advanceAfterSkip(set, in: session)
            }
            wiring.sync.requestPendingWriteFlush()
        } catch {
            wiring.sync.reportLocalWriteFailure(error)
        }
    }

    func deleteLog(for set: ExerciseSet) {
        do {
            let session = try actionSession(for: set)
            try wiring.logging.deleteLog(for: set)
            wiring.restTimer.cancel(
                ifOriginMatches: Self.activeSetID(for: set),
                originSetObjectID: ObjectIdentifier(set)
            )
            reconcileLiveActivity(for: session)
            focusManager.focus(on: set)
            wiring.sync.requestPendingWriteFlush()
        } catch {
            wiring.sync.reportLocalWriteFailure(error)
        }
    }

    func updateLoggedSet(_ set: ExerciseSet, as log: SetLog) {
        do {
            let session = try actionSession(for: set)
            let updatedSetID = Self.activeSetID(for: set)
            try wiring.logging.log(set, as: log)
            savedLoggedSetID = updatedSetID
            reconcileLiveActivity(for: session)
            if focusManager.expandedLoggedSetID == updatedSetID {
                focusManager.collapseLoggedSetReview()
            }
            wiring.sync.requestPendingWriteFlush()
        } catch {
            wiring.sync.reportLocalWriteFailure(error)
        }
    }

    @discardableResult
    func createSuperset(from source: Exercise, to target: Exercise, in session: Session) -> Bool {
        focusManager.createSuperset(from: source, to: target, in: session)
    }

    func dismissSuperset(containing exercise: Exercise, in session: Session) {
        cancelPairing()
        focusManager.dismissSuperset(containing: exercise, in: session)
    }

    @discardableResult
    func focusNextSupersetSet(for exercise: Exercise, in session: Session) -> Bool {
        var focused = false
        perform(.cut) {
            focused = focusManager.focusNextSupersetSet(for: exercise, in: session)
        }
        return focused
    }

    static func activeSetID(for set: ExerciseSet) -> ActiveSetID? {
        ActiveSetFocusManager.id(for: set)
    }

    private func perform(_ requested: SessionMotion?, _ change: () throws -> Void) rethrows {
        guard let requested, requested.runs(reducingMotion: wiring.motion.reducesMotion) else {
            try change()
            return
        }
        try wiring.motion.animate(requested, change)
    }

    private func actionSession(for set: ExerciseSet) throws -> Session {
        guard let session = set.exercise?.session else {
            throw SessionCoordinatorError.missingSession
        }

        if self.session !== session {
            bind(to: session)
        }

        return session
    }
}

extension SessionCoordinator {
    func cancelRestForSessionExit() {
        wiring.restTimer.dismiss()
        wiring.liveActivity.end()
    }

    func moveOn() {
        cancelRestForSessionExit()
        wiring.navigation.requestMoveOnCelebration()
    }

    func showSourceSession(of exercise: Exercise) {
        cancelPairing()
        guard let address = exercise.session?.address else { return }
        wiring.navigation.show(address)
    }

    func stage(in session: Session, lookup: LastPerformedLookupSnapshot) -> SessionStage {
        SessionStage(
            session: session,
            focus: focusManager.snapshot(in: session),
            savedLoggedSetID: savedLoggedSetID,
            pairingMode: pairingMode,
            liveEdge: liveEdgeContext(for: session),
            lookup: lookup
        )
    }

    private func liveEdgeContext(for session: Session) -> LiveEdgeContext {
        guard wiring.navigation.liveEdge(for: session).isAtLiveEdge else { return .browsedAway }
        return .atLiveEdge(canMoveOn: wiring.navigation.canMoveOn, openExercises: wiring.navigation.openExercises)
    }
}

extension SessionCoordinator {
    fileprivate func isSupersetMember(_ set: ExerciseSet) -> Bool {
        guard let exercise = set.exercise else { return false }
        return focusManager.isPaired(exercise)
    }

    fileprivate func startRest(afterLogging set: ExerciseSet, in session: Session, wasSupersetMember: Bool) {
        guard
            let restKind = RestTriggerPolicy.restKind(
                afterLogging: set,
                in: session,
                isSupersetMember: wasSupersetMember,
                isRestRunning: wiring.restTimer.isRunning
            )
        else { return }
        wiring.restTimer.start(
            duration: wiring.restDurations.restDuration(for: restKind),
            origin: Self.activeSetID(for: set),
            originSetObjectID: ObjectIdentifier(set),
            kind: restKind
        )
        startOrUpdateLiveActivity(afterLogging: set, in: session)
    }

    fileprivate func startOrUpdateLiveActivity(afterLogging set: ExerciseSet, in session: Session) {
        let event = LiveActivityProductionEvent(
            source: .userSetLog,
            outcome: .success,
            sessionScope: wiring.navigation.liveEdge(for: session).isAtLiveEdge ? .currentSession : .nonCurrentSession
        )
        guard
            LiveActivityCreationPolicy.shouldCreateOrUpdate(for: event),
            let restInterval = wiring.restTimer.interval
        else { return }

        guard
            let content = focusManager.liveActivityRestContent(
                afterLogging: set,
                in: session,
                restStartDate: restInterval.start,
                restEndDate: restInterval.end
            )
        else { return }

        wiring.liveActivity.startOrUpdate(
            restContent: content,
            sessionLabel: liveActivitySessionLabel(for: session)
        )
    }

    fileprivate func reconcileLiveActivity(for session: Session) {
        wiring.liveActivity.endIfInvalidated(at: wiring.navigation.liveEdge(for: session))
    }

    fileprivate func liveActivitySessionLabel(for session: Session) -> String {
        if let address = session.address {
            return "Week \(address.week) - Day \(address.day)"
        }
        return "Day \(session.dayNumber)"
    }
}

extension SessionCoordinator {
    @discardableResult
    func beginPairing(from exercise: Exercise, in session: Session) -> Bool {
        pairing.begin(from: exercise, in: session)
    }

    func cancelPairing() {
        pairing.cancel()
    }

    @discardableResult
    func handlePairingTap(on exercise: Exercise, in session: Session) -> PairingTapResult {
        pairing.handleTap(on: exercise, in: session)
    }
}
