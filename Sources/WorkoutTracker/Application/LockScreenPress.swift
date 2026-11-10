import Foundation

/// A press on one of the Lock Screen card's controls, with the phone locked or the app behind. Only
/// an RPE Chip writes: it logs the weight the card showed at the Reps and the RPE the athlete tapped,
/// through the card's store call, then does what a Dictation with the app behind does: starts the
/// rest, moves the card on to it, and flushes. Every decision lives here; the intents only run it.
@MainActor
final class LockScreenPress {
    enum Outcome: Equatable, Sendable {
        case logged(SetLog, at: ActiveSetID)
        /// The same chip again, as a chalky double tap presses it: the Set already holds this Set
        /// Log, so nothing changes and the next Set's card stays.
        case sameSetLog(at: ActiveSetID)
        /// The face the card is on after the press, which is its rest face when the Set has no
        /// such face or no card is up. Nothing was written.
        case turned(to: LockScreenFace)
        case notLogged(NotLogged)
    }

    /// Wrote nothing, and the Live Activity says why.
    enum NotLogged: Equatable, Sendable {
        /// The press carries a Set, Reps, or an RPE this build cannot read.
        case unreadable
        case noCurrentSession
        case sessionChanged
        /// The Set took another Set Log, or a skip, since the card drew. `setLog` reads it back.
        case setSettled(setLog: String?, set: LiveActivityDictationContent.WrittenSet)
        /// The card now offers another Set, or the Sheet no longer holds this one.
        case cardMovedOn
        /// The stage's card holds another weight than the one the Lock Screen showed.
        case cardChanged
        case writeFailed
        /// An RPE tap as the card turned to RPE, which the second tap of a double tap on a Reps Chip
        /// makes. The card that follows the readback still offers RPE for the same Reps.
        case tooSoonAfterReps
        /// A mic press is in flight, so the Set is the mic's: the Lock Screen's, or the card's in
        /// the app.
        case micBusy(SetDictation.Surface)
    }

    /// Which Set a press names, read off the store and the focus before anything changes.
    enum Target {
        /// The Set the card offers, still Pending and still showing the weight the press carries.
        case pending(SessionSetPosition, in: Session, LoggableSetIdentity)
        case settled(SessionSetPosition, in: Session, LoggableSetIdentity)
        case refuse(NotLogged)
    }

    /// What an RPE press does.
    enum Decision {
        case write(SetLog, to: SessionSetPosition, in: Session)
        case sameSetLog(at: ActiveSetID)
        case refuse(NotLogged)
    }

    /// Long enough to catch "Logged 235×12 @7" on the island against the Reps and RPE meant, which
    /// only the app can change, and to read why a press logged nothing.
    nonisolated static let readbackHold: Duration = .milliseconds(3500)

    private let app: WorkoutApplication
    private let dictation: SetDictation?
    private let focus: ActiveSetFocusManager
    private let liveActivity: any DictationLiveActivityAdapter
    private let settle: RPEFaceSettle
    private let clock: any ListeningClock
    private let writes: HeadlessWrites

    init(
        app: WorkoutApplication,
        dictation: SetDictation?,
        focus: ActiveSetFocusManager,
        restTimer: RestTimer,
        liveActivity: any DictationLiveActivityAdapter,
        settle: RPEFaceSettle,
        signIn: any SignInRestoring,
        clock: any ListeningClock
    ) {
        self.app = app
        self.dictation = dictation
        self.focus = focus
        self.liveActivity = liveActivity
        self.settle = settle
        self.clock = clock
        writes = HeadlessWrites(app: app, focus: focus, restTimer: restTimer, signIn: signIn, clock: clock)
    }

    /// Turns the card to `face` and writes nothing. `setIdentity` names the Set whose Set Log the
    /// Reps and RPE faces choose, and a press toward either refuses what a log would. The rest face
    /// and the Coach Note belong to whichever Set the card is on, so they name none and refuse nothing.
    @discardableResult
    func turn(to face: LockScreenFace, pressing setIdentity: String?) async -> Outcome {
        if let surface = micInFlight { return await turnWhileTheMicListens(surface, to: face, pressing: setIdentity) }
        focus.endHoldAfterSpokenWrite()
        guard face.choosesTheSetLog else { return .turned(to: await showCard(turnedTo: face)) }
        return await turnToTheChoices(face, pressing: setIdentity)
    }

    /// The mic has the Set, so the card stays on its face, and a press toward the choices says why.
    private func turnWhileTheMicListens(
        _ surface: SetDictation.Surface,
        to face: LockScreenFace,
        pressing setIdentity: String?
    ) async -> Outcome {
        guard face.choosesTheSetLog else { return .turned(to: liveActivity.restContent?.face ?? .rest) }
        return await refuseWhileTheMicListens(surface, pressing: setIdentity)
    }

    private func turnToTheChoices(_ face: LockScreenFace, pressing setIdentity: String?) async -> Outcome {
        switch target(of: setIdentity, choosing: face) {
        case .pending:
            let shown = await showCard(turnedTo: face)
            if case .rpe = shown {
                settle.rpeFaceShown(at: clock.now)
            }
            return .turned(to: shown)
        case .settled(let position, let session, _):
            return await refuse(
                .setSettled(setLog: position.set.setLog?.readback, set: .init(position, in: session)),
                pressing: setIdentity
            )
        case .refuse(let why):
            return await refuse(why, pressing: setIdentity)
        }
    }

    @discardableResult
    func logSet(setIdentity: String, reps: Int, rpe: String) async -> Outcome {
        if let surface = micInFlight { return await refuseWhileTheMicListens(surface, pressing: setIdentity) }
        guard settle.admitsRPEPress(at: clock.now) else {
            return await refuse(.tooSoonAfterReps, pressing: setIdentity, returningTo: .rpe(reps: reps))
        }
        // The card keeps a Set its mic wrote for the athlete to glance at and undo. A press with
        // the phone locked says they have moved on, as a press of the mic does.
        focus.endHoldAfterSpokenWrite()
        switch Self.decision(setIdentity: setIdentity, reps: reps, rpe: rpe, session: app.workout.currentSession, focus: focus) {
        case .write(let setLog, let position, let session):
            return await write(setLog, to: position, in: session)
        case .sameSetLog(let setID):
            return .sameSetLog(at: setID)
        case .refuse(let why):
            return await refuse(why, pressing: setIdentity)
        }
    }

    /// Where a mic press in flight began; nil with none.
    private var micInFlight: SetDictation.Surface? {
        guard let dictation, dictation.state.pressSetID != nil else { return nil }
        return dictation.pressSurface ?? .card
    }

    static func decision(setIdentity: String, reps: Int, rpe: String, session: Session?, focus: ActiveSetFocusManager) -> Decision {
        guard LockScreenOffer.repsRange.contains(reps), let rpe = RPE(text: rpe) else { return .refuse(.unreadable) }
        switch target(of: setIdentity, session: session, focus: focus) {
        case .pending(let position, let session, let identity):
            return .write(identity.setLog(reps: reps, rpe: rpe), to: position, in: session)
        case .settled(let position, let session, let identity):
            return settled(position, in: session, pressing: identity.setLog(reps: reps, rpe: rpe))
        case .refuse(let why):
            return .refuse(why)
        }
    }

    private func target(of setIdentity: String?, choosing face: LockScreenFace) -> Target {
        if case .rpe(let reps) = face, !LockScreenOffer.repsRange.contains(reps) { return .refuse(.unreadable) }
        guard let setIdentity else { return .refuse(.unreadable) }
        return Self.target(of: setIdentity, session: app.workout.currentSession, focus: focus)
    }

    /// The Set must still be the one the card offers, showing the weight the Lock Screen showed. A
    /// card that has shown nothing, as after the system ended the app, has nothing to disagree with.
    static func target(of setIdentity: String, session: Session?, focus: ActiveSetFocusManager) -> Target {
        guard let identity = LoggableSetIdentity(storageValue: setIdentity) else { return .refuse(.unreadable) }
        guard let session else { return .refuse(.noCurrentSession) }
        guard session.placement.coordinate == identity.session else { return .refuse(.sessionChanged) }
        return target(pressing: identity, in: session, focus: focus)
    }

    private static func target(pressing identity: LoggableSetIdentity, in session: Session, focus: ActiveSetFocusManager) -> Target {
        guard let pressed = set(identity.setID, in: session) else { return .refuse(.cardMovedOn) }
        guard pressed.set.isPending else { return .settled(pressed, in: session, identity) }
        guard focus.activeSet(in: session)?.setID == identity.setID else { return .refuse(.cardMovedOn) }
        guard focus.cardDraft(for: identity.setID).map({ $0.weight == identity.weight }) ?? true else { return .refuse(.cardChanged) }
        return .pending(pressed, in: session, identity)
    }

    private static func set(_ setID: ActiveSetID, in session: Session) -> SessionSetPosition? {
        SessionSetOrder.orderedSets(in: session).first { $0.setID == setID }
    }

    /// The Set a press's identity names in this Session; nil for one from another Session.
    private static func set(named setIdentity: String?, in session: Session) -> SessionSetPosition? {
        guard let identity = setIdentity.flatMap(LoggableSetIdentity.init(storageValue:)),
            identity.session == session.placement.coordinate
        else { return nil }
        return set(identity.setID, in: session)
    }

    private static func settled(_ pressed: SessionSetPosition, in session: Session, pressing setLog: SetLog) -> Decision {
        guard pressed.set.setLog != setLog else { return .sameSetLog(at: pressed.setID) }
        return .refuse(.setSettled(setLog: pressed.set.setLog?.readback, set: .init(pressed, in: session)))
    }

    private func showCard(turnedTo face: LockScreenFace) async -> LockScreenFace {
        guard let card = currentCard()?.turned(to: face) else { return .rest }
        if card != liveActivity.restContent {
            await liveActivity.refresh(card: card)
        }
        return card.face
    }

    /// In the stage's order (write, rest, then focus) and before anything is awaited, since a second
    /// press can arrive while the card draws.
    private func write(_ setLog: SetLog, to position: SessionSetPosition, in session: Session) async -> Outcome {
        // Read before the write, which dissolves a Superset when it logs a side's last Set.
        let wasSupersetMember = focus.isPaired(position.exercise)
        do {
            try app.workout.log(position.set, as: setLog)
        } catch {
            return await refuse(.writeFailed, pressing: nil)
        }
        let subject = writes.restSubject(afterLogging: position, in: session, wasSupersetMember: wasSupersetMember)
        focus.advanceAfterSpokenWrite(position.set, in: session, holding: false)
        switch subject {
        case .rest(let rest):
            let readback = LiveActivityDictationContent.Readback.logged(setLog.readback, to: .init(position, in: session))
            await liveActivity.show(rest, islandReading: readback, sessionLabel: session.liveActivityLabel)
            async let flushed: Void = writes.flush()
            await showCard(after: readback, on: .rest)
            await flushed
        case .set:
            await liveActivity.endRest()
            await writes.flush()
        }
        await showWhatTheFlushLeft()
        return .logged(setLog, at: position.setID)
    }

    /// With no rest running, the Lock Screen's recording has the Live Activity to itself, and a
    /// readback would end the activity the system records under. The app's mic records in the app,
    /// so a press over it always says why.
    private func refuseWhileTheMicListens(_ surface: SetDictation.Surface, pressing setIdentity: String?) async -> Outcome {
        guard surface == .card || liveActivity.restContent != nil else { return .notLogged(.micBusy(surface)) }
        return await refuse(.micBusy(surface), pressing: setIdentity)
    }

    /// Says why nothing was written, over the Set the card is on, else over the Set the press
    /// named, as a stale press on the Session's last Set does.
    private func refuse(
        _ why: NotLogged,
        pressing setIdentity: String?,
        returningTo face: LockScreenFace = .rest  // default: only a too-soon press proved the card was on RPE for its Reps
    ) async -> Outcome {
        guard let session = app.workout.currentSession else {
            await liveActivity.show(.noCurrentSession)
            return .notLogged(why)
        }
        guard let shown = focus.activeSet(in: session) ?? Self.set(named: setIdentity, in: session) else {
            await liveActivity.show(.noSetLeft)
            return .notLogged(why)
        }
        let readback = why.readback
        var set = LiveActivitySetContent(shown)
        set.pendingWrites = writes.pendingWriteCount
        await liveActivity.show(
            LiveActivityDictationContent(readback: readback, subject: .set(set)),
            sessionLabel: session.liveActivityLabel
        )
        if case .micBusy(.headless) = why {
            await showListening(after: readback, in: session)
        } else {
            await showCard(after: readback, on: face)
        }
        return .notLogged(why)
    }

    /// The readback holds, with nothing to tap, then the Lock Screen shows the Set the card is on,
    /// on `face` when that Set has it. The system suspends the app once the intent returns, so
    /// nothing could do this later. With no rest running, the activity has ended on the readback,
    /// which stays to be read.
    private func showCard(after readback: LiveActivityDictationContent.Readback, on face: LockScreenFace) async {
        guard liveActivity.restContent != nil else { return }
        await clock.sleep(until: clock.now + Self.readbackHold)
        guard let card = currentCard() else { return }
        await liveActivity.replace(readback, with: card.turned(to: face))
    }

    /// The Lock Screen's mic keeps listening under the readback, so "Listening…" comes back once it
    /// has been read. A mic that stopped in the meantime shows its own result, which the card
    /// follows.
    private func showListening(after readback: LiveActivityDictationContent.Readback, in session: Session) async {
        await clock.sleep(until: clock.now + Self.readbackHold)
        guard let setID = dictation?.state.pressSetID, let listenedFor = Self.set(setID, in: session) else {
            guard let card = currentCard() else { return }
            await liveActivity.replace(readback, with: card)
            return
        }
        let listening = LiveActivityDictationContent(readback: .listening, subject: .set(LiveActivitySetContent(listenedFor)))
        await liveActivity.show(listening, sessionLabel: session.liveActivityLabel)
    }

    /// A flush can empty the queue the card counted. The athlete may have turned the card while it
    /// ran, so the card keeps its face.
    private func showWhatTheFlushLeft() async {
        guard let running = liveActivity.restContent, let card = currentCard()?.keepingTheFace(of: running), card != running
        else { return }
        await liveActivity.refresh(card: card)
    }

    /// The Set the card is on, drawn afresh on its rest face.
    private func currentCard() -> LiveActivityRestContent? {
        guard
            let running = liveActivity.restContent,
            let session = app.workout.currentSession,
            let active = focus.activeSet(in: session)
        else { return nil }
        var card = LiveActivityRestContentBuilder.content(
            showing: active,
            in: session,
            reading: LoggablePressSource(focus: focus, history: app.lastPerformed.snapshot),
            restStartDate: running.restStartDate,
            restEndDate: running.restEndDate
        )
        card.pendingWrites = writes.pendingWriteCount
        return card
    }
}

/// When the Lock Screen card last turned to its RPE face, kept across presses for the app's life.
@MainActor
final class RPEFaceSettle {
    /// A press can land seconds after its tap, so a second tap on a Reps Chip can reach the RPE Chip
    /// that took its place. An RPE press this soon after the card turned writes nothing.
    nonisolated static let duration: Duration = .seconds(1)

    private var rpeFaceShownAt: Duration?

    init() {}

    func rpeFaceShown(at now: Duration) {
        rpeFaceShownAt = now
    }

    func admitsRPEPress(at now: Duration) -> Bool {
        guard let shownAt = rpeFaceShownAt else { return true }
        return now - shownAt >= Self.duration
    }
}

extension LockScreenPress.NotLogged {
    /// Why, as a client with no Live Activity reports it and the Live Activity reads it back.
    var caption: String {
        switch self {
        case .unreadable: "Couldn’t read that tap. Open to log"
        case .noCurrentSession: "No Current Session"
        case .sessionChanged: "The Session changed. Open to log"
        case .setSettled(let setLog, let set):
            "Set \(set.setOrdinal) of \(set.setsTotal) " + (setLog.map { "holds \($0)" } ?? "was skipped")
        case .cardMovedOn: "The card moved to another Set"
        case .cardChanged: "The weight changed. Open to log"
        case .writeFailed: "Couldn’t save. Open to log"
        case .tooSoonAfterReps: "Too soon after the Reps. Tap the RPE again"
        case .micBusy(.headless): "The mic is listening. Say the Set"
        case .micBusy(.card): "The app’s mic is listening. Open to log"
        }
    }

    /// A settled Set may not be the one the card has moved on to, so its readback names it. It leads
    /// with what the Set holds: two chips pressed at once log the first, and the second press must
    /// not read as losing the Set.
    fileprivate var readback: LiveActivityDictationContent.Readback {
        if case .setSettled(let setLog, let set) = self { return .settled(setLog: setLog, set) }
        return .notLogged(caption)
    }
}
