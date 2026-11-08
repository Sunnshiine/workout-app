import Foundation

/// A tap on an RPE Chip, with the phone locked or the app behind. It logs the values the Lock Screen
/// showed at the tapped RPE through the card's store call, then does what a Dictation with the app
/// behind does: starts the rest, moves the card on, reads back, and flushes. Every decision lives
/// here; the intent only runs it.
@MainActor
final class RPEChipPress {
    enum Outcome: Equatable, Sendable {
        case logged(SetLog, at: ActiveSetID)
        /// The same chip again, as a chalky double tap presses it: the Set already holds this Set
        /// Log, so nothing changes and the first press's readback stays.
        case sameSetLog(at: ActiveSetID)
        case notLogged(NotLogged)
        /// The card's mic is listening, and its readback says so.
        case micBusy
    }

    /// Wrote nothing, and the Live Activity says why.
    enum NotLogged: Equatable, Sendable {
        /// The press carries a Set or an RPE this build cannot read.
        case unreadable
        case noCurrentSession
        case sessionChanged
        /// The Set took another Set Log, or a skip, since the card drew. `setLog` reads it back.
        case setSettled(setLog: String?, set: LiveActivityDictationContent.WrittenSet)
        /// The card now offers another Set, or the Sheet no longer holds this one.
        case cardMovedOn
        /// The stage's card holds other values than the ones the Lock Screen showed.
        case cardChanged
        case writeFailed
    }

    /// What the press does, read off the store and the focus before anything changes.
    enum Decision {
        case write(SetLog, to: SessionSetPosition, in: Session)
        case sameSetLog(at: ActiveSetID)
        case refuse(NotLogged)
    }

    /// Long enough to catch "Logged 235×5 @7" against the RPE meant, which only the app can change,
    /// and to read why a press logged nothing. A second tap of a double tap finds no chip of the
    /// next Set under the thumb.
    nonisolated static let readbackHold: Duration = .milliseconds(3500)

    private let app: WorkoutApplication
    private let dictation: SetDictation?
    private let focus: ActiveSetFocusManager
    private let liveActivity: any DictationLiveActivityAdapter
    private let clock: any ListeningClock
    private let writes: HeadlessWrites

    init(
        app: WorkoutApplication,
        dictation: SetDictation?,
        focus: ActiveSetFocusManager,
        restTimer: RestTimer,
        liveActivity: any DictationLiveActivityAdapter,
        signIn: any SignInRestoring,
        clock: any ListeningClock
    ) {
        self.app = app
        self.dictation = dictation
        self.focus = focus
        self.liveActivity = liveActivity
        self.clock = clock
        writes = HeadlessWrites(app: app, focus: focus, restTimer: restTimer, signIn: signIn, clock: clock)
    }

    @discardableResult
    func run(setIdentity: String, rpe: String) async -> Outcome {
        guard dictation?.state.pressSetID == nil else { return .micBusy }
        // The card keeps a Set its mic wrote for the athlete to glance at and undo. A press with
        // the phone locked says they have moved on, as a press of the mic does.
        focus.endHoldAfterSpokenWrite()
        let current = app.workout.currentSession
        switch Self.decision(setIdentity: setIdentity, rpe: rpe, session: current, focus: focus) {
        case .write(let setLog, let position, let session):
            return await write(setLog, to: position, in: session)
        case .sameSetLog(let setID):
            return .sameSetLog(at: setID)
        case .refuse(let why):
            return await refuse(why, in: current)
        }
    }

    /// The Set must still be the one the card offers, showing what the Lock Screen showed. A card
    /// that has shown nothing, as after the system ended the app, has nothing to disagree with.
    static func decision(setIdentity: String, rpe: String, session: Session?, focus: ActiveSetFocusManager) -> Decision {
        guard let identity = LoggableSetIdentity(storageValue: setIdentity), let rpe = RPE(text: rpe) else {
            return .refuse(.unreadable)
        }
        guard let session else { return .refuse(.noCurrentSession) }
        guard session.placement.coordinate == identity.session else { return .refuse(.sessionChanged) }
        return decision(pressing: identity, at: rpe, in: session, focus: focus)
    }

    private static func decision(
        pressing identity: LoggableSetIdentity,
        at rpe: RPE,
        in session: Session,
        focus: ActiveSetFocusManager
    ) -> Decision {
        let setLog = identity.setLog(at: rpe)
        guard let pressed = SessionSetOrder.orderedSets(in: session).first(where: { $0.setID == identity.setID }) else {
            return .refuse(.cardMovedOn)
        }
        guard pressed.set.isPending else { return settled(pressed, in: session, pressing: setLog) }
        guard focus.activeSet(in: session)?.setID == identity.setID else { return .refuse(.cardMovedOn) }
        guard cardAgrees(with: identity, focus: focus) else { return .refuse(.cardChanged) }
        return .write(setLog, to: pressed, in: session)
    }

    private static func cardAgrees(with identity: LoggableSetIdentity, focus: ActiveSetFocusManager) -> Bool {
        guard let shown = focus.cardDraft(for: identity.setID) else { return true }
        return shown.weight == identity.weight && shown.reps == identity.reps
    }

    private static func settled(_ pressed: SessionSetPosition, in session: Session, pressing setLog: SetLog) -> Decision {
        guard pressed.set.setLog != setLog else { return .sameSetLog(at: pressed.setID) }
        return .refuse(.setSettled(setLog: pressed.set.setLog?.readback, set: .init(pressed, in: session)))
    }

    /// In the stage's order (write, rest, then focus) and before anything is awaited, since a second
    /// press can arrive while the readback draws.
    private func write(_ setLog: SetLog, to position: SessionSetPosition, in session: Session) async -> Outcome {
        // Read before the write, which dissolves a Superset when it logs a side's last Set.
        let wasSupersetMember = focus.isPaired(position.exercise)
        do {
            try app.workout.log(position.set, as: setLog)
        } catch {
            return await refuse(.writeFailed, in: session)
        }
        let subject = writes.restSubject(afterLogging: position, in: session, wasSupersetMember: wasSupersetMember)
        focus.advanceAfterSpokenWrite(position.set, in: session, holding: false)
        let readback = LiveActivityDictationContent.Readback.logged(setLog.readback, to: .init(position, in: session))
        await liveActivity.show(LiveActivityDictationContent(readback: readback, subject: subject), sessionLabel: session.liveActivityLabel)
        async let flushed: Void = writes.flush()
        await showCard(after: readback)
        await flushed
        await showWhatTheFlushLeft()
        return .logged(setLog, at: position.setID)
    }

    private func refuse(_ why: NotLogged, in session: Session?) async -> Outcome {
        guard let session else {
            await liveActivity.show(.noCurrentSession)
            return .notLogged(why)
        }
        guard let active = focus.activeSet(in: session) else {
            await liveActivity.show(.noSetLeft(session: session.liveActivityLabel))
            return .notLogged(why)
        }
        let readback = why.readback
        await liveActivity.show(
            LiveActivityDictationContent(readback: readback, subject: .set(LiveActivitySetContent(active))),
            sessionLabel: session.liveActivityLabel
        )
        await showCard(after: readback)
        return .notLogged(why)
    }

    /// The readback holds, with no chips to tap, then the Lock Screen offers the Set the card is on.
    /// The system suspends the app once the intent returns, so nothing could do this later. With
    /// no rest running, the activity has ended on the readback, which stays to be read.
    private func showCard(after readback: LiveActivityDictationContent.Readback) async {
        guard liveActivity.restContent != nil else { return }
        await clock.sleep(until: clock.now + Self.readbackHold)
        guard let card = currentCard() else { return }
        await liveActivity.replace(readback, with: card)
    }

    /// A flush that outlasted the readback can empty the queue the card counted.
    private func showWhatTheFlushLeft() async {
        guard let card = currentCard(), card != liveActivity.restContent else { return }
        await liveActivity.refresh(card: card)
    }

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
        card.pendingWrites = (try? app.sync.fetchPendingWriteRecords().count) ?? 0
        return card
    }
}

extension RPEChipPress.NotLogged {
    /// Why, as a client with no Live Activity reports it and the Live Activity reads it back.
    var caption: String {
        switch self {
        case .unreadable: "Couldn’t read that tap. Open to log"
        case .noCurrentSession: "No Current Session"
        case .sessionChanged: "The Session changed. Open to log"
        case .setSettled(let setLog, let set):
            "Set \(set.setOrdinal) of \(set.setsTotal) " + (setLog.map { "holds \($0)" } ?? "was skipped")
        case .cardMovedOn: "The card moved to another Set"
        case .cardChanged: "The card changed. Open to log"
        case .writeFailed: "Couldn’t save. Open to log"
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

/// What the Lock Screen offers for the Current Session's active Set, for a client with no Live Activity.
public struct LockScreenOfferReport: Encodable, Equatable, Sendable {
    public struct Offer: Encodable, Equatable, Sendable {
        public let weight: String
        public let reps: Int
        public let rpeChoices: [String]
        public let prescribedRPE: String?
        public let setIdentity: String
    }

    /// Nil with no Pending Set left in the Current Session.
    public let set: SetAddress?
    public let exercise: String?
    public let lastPerformed: String?
    /// Nil when the card shows no RPE Chips.
    public let offer: Offer?
}

/// What one press did. `reason` says why when it logged nothing.
public struct RPEChipPressReport: Encodable, Equatable, Sendable {
    public enum Outcome: String, Encodable, Sendable {
        case logged, sameSetLog, notLogged
    }

    public let outcome: Outcome
    public let set: SetAddress?
    public let setLog: String?
    public let reason: String?
    public let pendingWriteCount: Int
}

extension WorkoutApplication {
    /// The card the Lock Screen draws, from a card fresh in this process: what no client has edited.
    public func lockScreenOffer() -> LockScreenOfferReport {
        let session = workout.currentSession
        let focus = ActiveSetFocusManager(session: session)
        guard let session, let active = focus.activeSet(in: session) else {
            return LockScreenOfferReport(set: nil, exercise: nil, lastPerformed: nil, offer: nil)
        }
        let history = lastPerformed.snapshot
        let press = LoggablePressContent(for: active, following: session, shownBy: focus, history: history)
        return LockScreenOfferReport(
            set: SetAddress(active.setID, in: session),
            exercise: active.exercise.exerciseName.entered,
            lastPerformed: active.exercise.lastPerformedLines(in: history).first,
            offer: LockScreenOfferReport.Offer(press)
        )
    }

    /// `RPEChipPress`'s decision and write. The rest, the focus, and the Live Activity it goes on to
    /// move live in the app's process, so a client with no stage has none to move.
    public func pressRPEChip(setIdentity: String, rpe: String) throws -> RPEChipPressReport {
        let session = workout.currentSession
        let focus = ActiveSetFocusManager(session: session)
        switch RPEChipPress.decision(setIdentity: setIdentity, rpe: rpe, session: session, focus: focus) {
        case .write(let setLog, let position, let session):
            try workout.log(position.set, as: setLog)
            return RPEChipPressReport(
                outcome: .logged,
                set: SetAddress(position.setID, in: session),
                setLog: setLog.formatted,
                reason: nil,
                pendingWriteCount: try sync.fetchPendingWriteRecords().count
            )
        case .sameSetLog(let setID):
            return RPEChipPressReport(
                outcome: .sameSetLog,
                set: session.flatMap { SetAddress(setID, in: $0) },
                setLog: nil,
                reason: nil,
                pendingWriteCount: try sync.fetchPendingWriteRecords().count
            )
        case .refuse(let why):
            return RPEChipPressReport(
                outcome: .notLogged,
                set: nil,
                setLog: nil,
                reason: why.caption,
                pendingWriteCount: try sync.fetchPendingWriteRecords().count
            )
        }
    }
}

extension LockScreenOfferReport.Offer {
    fileprivate init?(_ press: LoggablePressContent) {
        guard case .ready(let weight, let reps, let rpeChoices, let prescribedRPE, let setIdentity) = press else { return nil }
        self.init(weight: weight, reps: reps, rpeChoices: rpeChoices, prescribedRPE: prescribedRPE, setIdentity: setIdentity)
    }
}

extension SetAddress {
    fileprivate init?(_ setID: ActiveSetID, in session: Session) {
        guard let address = session.placement.coordinate?.address else { return nil }
        self.init(exercise: ExerciseAddress(session: address, order: setID.exerciseOrder), index: setID.setIndex)
    }
}
