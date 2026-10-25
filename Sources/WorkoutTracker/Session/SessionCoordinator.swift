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

    @ObservationIgnored let focusManager: ActiveSetFocusManager
    @ObservationIgnored private let pairing: SupersetPairing
    @ObservationIgnored let wiring: SessionWiring
    @ObservationIgnored private var liveEdgeReconcile: Task<Void, Never>?
    @ObservationIgnored private let transitionClock: any SessionTransitionClock
    /// Nil leaves the mic off every card.
    @ObservationIgnored let dictation: SetDictation?
    @ObservationIgnored var dictatingSession: Session?
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
        self.session = session
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

    /// The athlete is now viewing `session`. Re-points the coordinator at it, with focus
    /// re-seeded from its first Pending Set, and re-checks the rest Live Activity.
    func view(_ session: Session) {
        bind(to: session)
        reconcileLiveActivity()
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
        self.session = session
        savedLoggedSetID = nil
        cancelPairing()
        cancelSpokenWriteHold()
        dictation?.dismiss()
        focusManager.reset(to: session)
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
    private func write(_ write: CardWrite, to set: ExerciseSet, as mode: SetCardMode, from source: WriteSource) -> Bool {
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

/// How a write reached the card. A tap moves the card on at once; a spoken write keeps the Set on
/// the card first, so the athlete can glance at what was heard and undo it.
private enum WriteSource {
    case card
    case speech
}

private enum CardWrite {
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

extension SessionCoordinator {
    /// How long the card keeps a Set written by speech before it moves on.
    static let spokenWriteHold: Duration = .seconds(4)

    /// Nil keeps the mic off the card: no transcriber, or a Set the card neither logs nor reviews.
    func cardDictation(for slot: SetCardSlot) -> SetCardDictation? {
        guard let dictation, spokenWriteMode(for: slot.set) == slot.mode.cardMode, let setID = Self.activeSetID(for: slot.set) else {
            return nil
        }
        return SetCardDictation(dictation.state, for: setID)
    }

    /// How the card writes a Spoken Set for `set`: as a log of a Pending Set, or as a save over the
    /// logged Set under review. Nil for any other Set, which takes nothing said.
    private func spokenWriteMode(for set: ExerciseSet) -> SetCardMode? {
        guard let setID = Self.activeSetID(for: set) else { return nil }
        if set.isPending { return .logging }
        if set.state == .logged, focusManager.expandedLoggedSetID == setID { return .reviewingLogged }
        return nil
    }

    func startDictation(for set: ExerciseSet) {
        guard let dictation, let setID = Self.activeSetID(for: set), let session = stagedSession(of: set),
            let mode = spokenWriteMode(for: set), dictation.start(for: setID)
        else { return }
        dictatingSession = session
        dictatingMode = mode
    }

    /// The Session on stage, when `set` is in it.
    private func stagedSession(of set: ExerciseSet) -> Session? {
        guard let session, set.exercise?.session === session else { return nil }
        return session
    }

    /// The card reports what it shows for `set` as the athlete changes it, which fills what a
    /// Spoken Set leaves unsaid, from the card's mic or a press with the phone locked alike.
    func cardShows(_ draft: SetLogDraft, for set: ExerciseSet) {
        guard let setID = Self.activeSetID(for: set) else { return }
        focusManager.cardShows(draft, for: setID)
    }

    /// Writes what the athlete said through the same paths as the card's Log and skip, with what
    /// they left unsaid read from what `set`'s card shows. A press begun on another Session or for
    /// another Set writes nothing, as `write(_:heardFor:in:)` says of a Set the card no longer
    /// writes as the press began.
    func finishDictation(of set: ExerciseSet) async -> SetDictation.Outcome? {
        guard let dictation, let setID = dictation.state.pressSetID else { return nil }
        guard let session = sessionOfPress(for: setID, releasedOn: set) else {
            await dictation.cancel()
            return nil
        }
        return write(await dictation.finish(for: setID, in: spokenSetContext(for: set)), heardFor: setID, in: session)
    }

    func spokenSetContext(for set: ExerciseSet) -> SpokenSetContext {
        SpokenSetContext(for: set, shownBy: focusManager, history: wiring.history())
    }

    /// The Session `setID`'s press began in, while it is on stage and `set` is that Set in it.
    private func sessionOfPress(for setID: ActiveSetID, releasedOn set: ExerciseSet) -> Session? {
        guard let session, session === dictatingSession, Self.activeSetID(for: set) == setID, set.exercise?.session === session else {
            return nil
        }
        return session
    }

    func pendingSet(at setID: ActiveSetID, in session: Session) -> ExerciseSet? {
        guard self.session === session, let set = session.set(at: setID), set.isPending else { return nil }
        return set
    }

    /// The card writes what was said as it would a tap, in the mode the press began in. A Set the
    /// card no longer writes that way once the transcript is in, as one logged by hand during a
    /// press for its log, takes nothing, and neither does a write the mode refuses, as a skip said
    /// over a review: its outcome goes, so the card answers no write it did not make.
    func write(_ outcome: SetDictation.Outcome?, heardFor setID: ActiveSetID, in session: Session) -> SetDictation.Outcome? {
        guard let outcome else { return nil }
        guard let (set, mode) = spokenWriteTarget(at: setID, in: session) else {
            dictation?.dismiss()
            return nil
        }
        guard let cardWrite = CardWrite(outcome) else { return outcome }
        guard write(cardWrite, to: set, as: mode, from: .speech) else {
            dictation?.dismiss()
            return nil
        }
        return outcome
    }

    /// The Set at `setID` and the mode the press began in, while the card still writes it that way.
    private func spokenWriteTarget(at setID: ActiveSetID, in session: Session) -> (ExerciseSet, SetCardMode)? {
        guard self.session === session, let set = session.set(at: setID), let mode = dictatingMode, spokenWriteMode(for: set) == mode
        else { return nil }
        return (set, mode)
    }

    /// Stops the press for `set` whose control left the screen, writing nothing. A control that
    /// leaves while another card's press runs, as an outgoing card's can after the incoming one
    /// starts listening, stops nothing.
    func cancelDictation(of set: ExerciseSet) async {
        guard let dictation, let setID = dictation.state.pressSetID, Self.activeSetID(for: set) == setID,
            set.exercise?.session === dictatingSession
        else { return }
        await dictation.cancel()
    }

    func dismissDictation() {
        dictation?.dismiss()
    }

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

@MainActor
extension Session {
    fileprivate func set(at setID: ActiveSetID) -> ExerciseSet? {
        exercises.first { $0.order == setID.exerciseOrder }?.sets.first { $0.index == setID.setIndex }
    }
}
