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
    /// The Session on stage, by the coordinate a sync's re-parse keeps. Nil until the stage binds.
    private(set) var sessionCoordinate: SessionCoordinate?
    private(set) var savedLoggedSetID: ActiveSetID?

    @ObservationIgnored let focusManager: ActiveSetFocusManager
    @ObservationIgnored private let pairing: SupersetPairing
    @ObservationIgnored let wiring: SessionWiring
    @ObservationIgnored private var liveEdgeReconcile: Task<Void, Never>?
    @ObservationIgnored private let transitionClock: any SessionTransitionClock
    /// Nil leaves the mic off every card.
    @ObservationIgnored let dictation: SetDictation?
    /// The Set the running press or hands-free listen began on, by the coordinates a sync's
    /// re-parse keeps. Its Session is the one the press began on.
    @ObservationIgnored var dictatingSet: SetCoordinates.ID?
    /// How the card writes the running press's Spoken Set, fixed when the press began.
    @ObservationIgnored var dictatingMode: SetCardMode?
    @ObservationIgnored private var spokenWriteHoldTask: Task<Void, Never>?

    init(
        session: Session? = nil,
        wiring: SessionWiring,
        transitionClock: any SessionTransitionClock = TaskSessionTransitionClock(),
        dictation: SetDictation? = nil,
        focus: ActiveSetFocusManager? = nil
    ) {
        sessionCoordinate = session?.placement.coordinate
        self.wiring = wiring
        self.transitionClock = transitionClock
        self.dictation = dictation
        // A focus handed in is the process's, which a headless Dictation reads too. It keeps the
        // Session it is about until the stage binds, since SwiftUI builds a coordinator it then
        // throws away on every pass over the Session screen's init.
        let focusManager = focus ?? ActiveSetFocusManager(session: session)
        self.focusManager = focusManager
        self.pairing = SupersetPairing(focusManager: focusManager, clock: transitionClock)
        reconcileOnEachLiveEdgeChange()
    }

    deinit {
        liveEdgeReconcile?.cancel()
        spokenWriteHoldTask?.cancel()
    }

    var activeSetID: ActiveSetID? { focusManager.activeSetID }
    var restTimer: RestTimer { wiring.restTimer }
    var expandedLoggedSetID: ActiveSetID? { focusManager.expandedLoggedSetID }
    var pairingMode: PairingMode { pairing.mode }
    var supersetFusions: Int { pairing.fusions }

    /// The athlete is now viewing `session`, and the rest Live Activity is re-checked. A Session
    /// the stage is not on re-points the coordinator at it, with focus re-seeded from its first
    /// Pending Set. The Session on stage, parsed again by a sync, keeps what the athlete was doing.
    func view(_ session: Session) {
        if isOnStage(session) {
            follow(session)
        } else {
            bind(to: session)
        }
        reconcileLiveActivity()
    }

    /// True for the Session on stage, as itself or parsed again by a sync. A Detached Session is
    /// on no stage.
    func isOnStage(_ session: Session?) -> Bool {
        guard let coordinate = session?.placement.coordinate else { return false }
        return coordinate == sessionCoordinate
    }

    /// The Current Session, while it is the one at `coordinate`: the Session a press or a listen
    /// began on, parsed again by any sync that landed while it ran.
    func currentSession(at coordinate: SessionCoordinate) -> Session? {
        guard let current = wiring.navigation.currentSession, current.placement.coordinate == coordinate else { return nil }
        return current
    }

    /// Re-checks the rest Live Activity at the Viewed Session's live edge. The one reconciler, run
    /// after every Session verb and whenever the store's live edge changes.
    private func reconcileLiveActivity() {
        wiring.liveActivity.endIfInvalidated(at: wiring.navigation.liveEdge)
    }

    /// Covers every store-driven change to the live edge: a sync replacing the Block, Make Current,
    /// Move On, a reload, and navigating. The observation fires in the store's `willSet`, before
    /// the new value lands, so the reconcile waits one main-actor turn and reads the settled store.
    /// Every change in that turn lands in the one reconcile. Listening again before reconciling
    /// keeps a change made during the reconcile from being missed.
    private func reconcileOnEachLiveEdgeChange() {
        withObservationTracking {
            _ = wiring.navigation.liveEdge
        } onChange: { [weak self] in
            // The navigation adapter changes only on the main actor, so its change notice runs there.
            MainActor.assumeIsolated {
                self?.liveEdgeReconcile = Task { [weak self] in
                    guard let self else { return }
                    reconcileOnEachLiveEdgeChange()
                    reconcileLiveActivity()
                }
            }
        }
    }

    private func bind(to session: Session) {
        sessionCoordinate = session.placement.coordinate
        savedLoggedSetID = nil
        cancelPairing()
        cancelSpokenWriteHold()
        dictation?.dismiss()
        focusManager.reset(to: session)
        answerEntry()
    }

    /// The focus, a review, a held Set, and a press under way carry over to the Session parsed
    /// again. A pairing under way ends, as on a bind, since its confirmation fuses the Exercises it
    /// began with.
    private func follow(_ session: Session) {
        cancelPairing()
        perform(nil) { focusManager.follow(session) }
        answerEntry()
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

    func jump(to set: ExerciseSet) {
        perform(focusManager.motion(forFocusing: set)) {
            focusManager.open(set)
        }
    }

    func log(_ set: ExerciseSet, as log: SetLog) {
        self.log(set, as: log, from: .card)
    }

    func log(_ setLog: SetLog, for slot: SetCardSlot) {
        write(.log(setLog), to: slot.set, as: slot.mode.cardMode, from: .card)
    }

    func skip(_ set: ExerciseSet) {
        skip(set, from: .card)
    }

    func skip(for slot: SetCardSlot) {
        write(.skip, to: slot.set, as: slot.mode.cardMode, from: .card)
    }

    /// The one path from the card to the store, for a tap and a Spoken Set alike. Logging writes
    /// the Set and moves on; reviewing saves over a logged Set and moves nothing, so a review takes
    /// no skip. A held Set takes no write from its card: only its Clear menu changes it.
    @discardableResult
    func write(_ write: CardWrite, to set: ExerciseSet, as mode: SetCardMode, from source: WriteSource) -> Bool {
        switch (mode, write) {
        case (.logging, .log(let setLog)): log(set, as: setLog, from: source)
        case (.logging, .skip): skip(set, from: source)
        case (.reviewingLogged, .log(let setLog)): updateLoggedSet(set, as: setLog)
        case (.reviewingLogged, .skip), (.held, _): return false
        }
        return true
    }

    private func log(_ set: ExerciseSet, as log: SetLog, from source: WriteSource) {
        do {
            let session = try actionSession(for: set)
            let wasSupersetMember = isSupersetMember(set)
            try perform(.momentumFlow) {
                try wiring.logging.log(set, as: log)
                startRest(afterLogging: set, in: session, wasSupersetMember: wasSupersetMember)
                reconcileLiveActivity()
                switch source {
                case .card: advanceAfterLog(set, in: session)
                case .speech: advanceAfterSpokenWrite(set, in: session, wasSupersetMember: wasSupersetMember)
                }
            }
            wiring.sync.requestPendingWriteFlush()
        } catch {
            wiring.sync.reportLocalWriteFailure(error)
        }
    }

    private func skip(_ set: ExerciseSet, from source: WriteSource) {
        do {
            let session = try actionSession(for: set)
            let wasSupersetMember = isSupersetMember(set)
            try perform(.skipFadeUp) {
                try wiring.logging.skip(set)
                reconcileLiveActivity()
                switch source {
                case .card: advanceAfterSkip(set, in: session)
                case .speech: advanceAfterSpokenWrite(set, in: session, wasSupersetMember: wasSupersetMember)
                }
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
            wiring.restTimer.cancelRest(startedBy: set)
            reconcileLiveActivity()
            perform(nil) { focusManager.focus(on: set) }
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
            reconcileLiveActivity()
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

    /// Every change to which Set the card shows runs through here, so a press's rejection or fill
    /// never outlives the card it was shown on.
    func perform(_ requested: SessionMotion?, _ change: () throws -> Void) rethrows {
        dictation?.dismiss()
        guard let requested, requested.runs(reducingMotion: wiring.motion.reducesMotion) else {
            try change()
            return
        }
        try wiring.motion.animate(requested, change)
    }

    /// A Set of a Detached Session names no stage, so it neither moves the stage nor writes.
    private func actionSession(for set: ExerciseSet) throws -> Session {
        guard let session = set.exercise?.session else {
            throw SessionCoordinatorError.missingSession
        }
        guard session.placement.coordinate != nil else { throw WorkoutLoggingError.detachedSession }

        if !isOnStage(session) {
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

extension SessionCoordinator {
    /// How a write reached the card. A tap moves the card on at once; a spoken write keeps the Set
    /// on the card first, so the athlete can glance at what was heard and undo it.
    enum WriteSource {
        case card
        case speech
    }

    enum CardWrite {
        case log(SetLog)
        case skip

        /// Nil for an outcome that writes nothing, as a draft filled or a transcript rejected.
        init?(_ outcome: SetDictation.Outcome) {
            switch outcome {
            case .logged(let setLog, _): self = .log(setLog)
            case .skipped: self = .skip
            case .filled, .rejected: return nil
            }
        }
    }
}

extension SessionCoordinator {
    /// How long the card keeps a Set written by speech before it moves on.
    static let spokenWriteHold: Duration = .seconds(4)

    /// The athlete opened the held Set's Clear menu: its time stops, and the card keeps the Set until
    /// the menu closes or a Clear undoes the write.
    func suspendSpokenWriteHold() {
        guard focusManager.isHoldingSpokenWrite else { return }
        cancelSpokenWriteHold()
    }

    /// The athlete touched the held card or closed its Clear menu without a Clear, or its time ran
    /// out: it moves on now. A hold already ended by a tap or a Clear stays ended.
    func endSpokenWriteHold() {
        guard focusManager.isHoldingSpokenWrite else { return }
        perform(.momentumFlow) { focusManager.endHoldAfterSpokenWrite() }
    }

    /// A Superset's stage shows no held Set, as it shows no review, so a spoken write there moves
    /// on at once.
    fileprivate func advanceAfterSpokenWrite(_ set: ExerciseSet, in session: Session, wasSupersetMember: Bool) {
        guard focusManager.advanceAfterSpokenWrite(set, in: session, holding: !wasSupersetMember) else { return }
        spokenWriteHoldTask?.cancel()
        let clock = transitionClock
        spokenWriteHoldTask = Task { @MainActor [weak self] in
            await clock.sleep(for: Self.spokenWriteHold)
            guard !Task.isCancelled else { return }
            self?.endSpokenWriteHold()
        }
    }

    private func cancelSpokenWriteHold() {
        spokenWriteHoldTask?.cancel()
        spokenWriteHoldTask = nil
    }
}
