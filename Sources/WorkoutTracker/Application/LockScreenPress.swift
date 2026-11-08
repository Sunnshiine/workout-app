import Foundation

/// A tap on one of the Lock Screen card's chips, with the phone locked or the app behind. A Reps
/// Chip turns the row to RPE and writes nothing. An RPE Chip logs the weight the card showed at the
/// Reps and the RPE the athlete tapped, through the card's store call, then does what a Dictation
/// with the app behind does: starts the rest, moves the card on, reads back, and flushes. Every
/// decision lives here; the intents only run it.
@MainActor
final class LockScreenPress {
    enum Outcome: Equatable, Sendable {
        case logged(SetLog, at: ActiveSetID)
        /// The same chip again, as a chalky double tap presses it: the Set already holds this Set
        /// Log, so nothing changes and the first press's readback stays.
        case sameSetLog(at: ActiveSetID)
        /// The row now offers RPE for these Reps, or Reps again for nil. Nothing was written.
        case choseReps(Int?)
        /// An RPE tap as the row turned to RPE, which the second tap of a double tap on a Reps Chip
        /// makes. Nothing was written, and the row stays as it is.
        case tooSoonAfterReps
        case notLogged(NotLogged)
        /// The card's mic is listening, and its readback says so.
        case micBusy
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

    /// Long enough to catch "Logged 235×12 @7" against the Reps and RPE meant, which only the app
    /// can change, and to read why a press logged nothing. A second tap of a double tap finds no
    /// chip of the next Set under the thumb.
    nonisolated static let readbackHold: Duration = .milliseconds(3500)

    private let app: WorkoutApplication
    private let dictation: SetDictation?
    private let focus: ActiveSetFocusManager
    private let liveActivity: any DictationLiveActivityAdapter
    private let rows: LockScreenRows
    private let clock: any ListeningClock
    private let writes: HeadlessWrites

    init(
        app: WorkoutApplication,
        dictation: SetDictation?,
        focus: ActiveSetFocusManager,
        restTimer: RestTimer,
        liveActivity: any DictationLiveActivityAdapter,
        rows: LockScreenRows,
        signIn: any SignInRestoring,
        clock: any ListeningClock
    ) {
        self.app = app
        self.dictation = dictation
        self.focus = focus
        self.liveActivity = liveActivity
        self.rows = rows
        self.clock = clock
        writes = HeadlessWrites(app: app, focus: focus, restTimer: restTimer, signIn: signIn, clock: clock)
    }

    /// Turns the row to RPE for `reps`, or back to Reps for nil. The Reps live on the card alone:
    /// each RPE Chip carries them, so a row drawn again from scratch can never log other Reps.
    @discardableResult
    func chooseReps(setIdentity: String, reps: Int?) async -> Outcome {
        guard dictation?.state.pressSetID == nil else { return .micBusy }
        focus.endHoldAfterSpokenWrite()
        let current = app.workout.currentSession
        switch LockScreenOffer.admits(reps) ? Self.target(of: setIdentity, session: current, focus: focus) : .refuse(.unreadable) {
        case .pending:
            await showRow(choosing: reps)
            return .choseReps(reps)
        case .settled(let position, let session, _):
            return await refuse(.setSettled(setLog: position.set.setLog?.readback, set: .init(position, in: session)), in: current)
        case .refuse(let why):
            return await refuse(why, in: current)
        }
    }

    @discardableResult
    func logSet(setIdentity: String, reps: Int, rpe: String) async -> Outcome {
        guard dictation?.state.pressSetID == nil else { return .micBusy }
        guard rows.admitsRPEPress(at: clock.now) else { return .tooSoonAfterReps }
        // The card keeps a Set its mic wrote for the athlete to glance at and undo. A press with
        // the phone locked says they have moved on, as a press of the mic does.
        focus.endHoldAfterSpokenWrite()
        let current = app.workout.currentSession
        switch Self.decision(setIdentity: setIdentity, reps: reps, rpe: rpe, session: current, focus: focus) {
        case .write(let setLog, let position, let session):
            return await write(setLog, to: position, in: session)
        case .sameSetLog(let setID):
            return .sameSetLog(at: setID)
        case .refuse(let why):
            return await refuse(why, in: current)
        }
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

    /// The Set must still be the one the card offers, showing the weight the Lock Screen showed. A
    /// card that has shown nothing, as after the system ended the app, has nothing to disagree with.
    static func target(of setIdentity: String, session: Session?, focus: ActiveSetFocusManager) -> Target {
        guard let identity = LoggableSetIdentity(storageValue: setIdentity) else { return .refuse(.unreadable) }
        guard let session else { return .refuse(.noCurrentSession) }
        guard session.placement.coordinate == identity.session else { return .refuse(.sessionChanged) }
        return target(pressing: identity, in: session, focus: focus)
    }

    private static func target(pressing identity: LoggableSetIdentity, in session: Session, focus: ActiveSetFocusManager) -> Target {
        guard let pressed = SessionSetOrder.orderedSets(in: session).first(where: { $0.setID == identity.setID }) else {
            return .refuse(.cardMovedOn)
        }
        guard pressed.set.isPending else { return .settled(pressed, in: session, identity) }
        guard focus.activeSet(in: session)?.setID == identity.setID else { return .refuse(.cardMovedOn) }
        guard focus.cardDraft(for: identity.setID).map({ $0.weight == identity.weight }) ?? true else { return .refuse(.cardChanged) }
        return .pending(pressed, in: session, identity)
    }

    private static func settled(_ pressed: SessionSetPosition, in session: Session, pressing setLog: SetLog) -> Decision {
        guard pressed.set.setLog != setLog else { return .sameSetLog(at: pressed.setID) }
        return .refuse(.setSettled(setLog: pressed.set.setLog?.readback, set: .init(pressed, in: session)))
    }

    private func showRow(choosing reps: Int?) async {
        guard var card = currentCard(), case .ready(var offer) = card.press else { return }
        offer.chosenReps = reps
        card.press = .ready(offer)
        await liveActivity.refresh(card: card)
        if reps != nil {
            rows.rpeRowShown(at: clock.now)
        }
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
        var set = LiveActivitySetContent(active)
        set.pendingWrites = writes.pendingWriteCount
        let content = LiveActivityDictationContent(readback: readback, subject: .set(set))
        await liveActivity.show(content, sessionLabel: session.liveActivityLabel)
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
        card.pendingWrites = writes.pendingWriteCount
        return card
    }
}

/// When the Lock Screen's row last turned from Reps to RPE, kept across presses for the app's life.
@MainActor
final class LockScreenRows {
    /// A press can land seconds after its tap, so a second tap on a Reps Chip can reach the RPE Chip
    /// that took its place. An RPE press this soon after the row turned writes nothing.
    nonisolated static let rpeRowSettle: Duration = .seconds(1)

    private var rpeRowShownAt: Duration?

    init() {}

    func rpeRowShown(at now: Duration) {
        rpeRowShownAt = now
    }

    func admitsRPEPress(at now: Duration) -> Bool {
        guard let shownAt = rpeRowShownAt else { return true }
        return now - shownAt >= Self.rpeRowSettle
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
        public let repChoices: [Int]
        public let prescribedReps: [Int]
        public let rpeChoices: [String]
        public let prescribedRPE: String?
        public let setIdentity: String
    }

    /// Nil with no Pending Set left in the Current Session.
    public let set: SetAddress?
    public let exercise: String?
    /// The weight the card holds, as the Set Log writes it; nil when it holds none.
    public let weight: String?
    public let prescribedReps: String?
    public let prescribedLoad: String?
    /// The Cadence and the Coach Note on the card's one line.
    public let guidance: String?
    /// The timed effort the card's Start opens the app to count, as `10 s hold`.
    public let start: String?
    /// Nil when the card shows no chips.
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
            return LockScreenOfferReport(
                set: nil,
                exercise: nil,
                weight: nil,
                prescribedReps: nil,
                prescribedLoad: nil,
                guidance: nil,
                start: nil,
                offer: nil
            )
        }
        let card = LiveActivityRestContentBuilder.content(
            showing: active,
            in: session,
            reading: LoggablePressSource(focus: focus, history: lastPerformed.snapshot),
            restStartDate: .distantPast,
            restEndDate: .distantPast
        )
        return LockScreenOfferReport(
            set: SetAddress(active.setID, in: session),
            exercise: card.exerciseName,
            weight: card.weightValue.isEmpty ? nil : card.weightValue,
            prescribedReps: card.prescribedReps,
            prescribedLoad: card.prescribedLoad,
            guidance: card.guidance,
            start: card.start?.effort.controlLabel,
            offer: LockScreenOfferReport.Offer(card.press)
        )
    }

    /// `LockScreenPress`'s decision and write for an RPE Chip pressed after a Reps Chip. The rest,
    /// the focus, and the Live Activity it goes on to move live in the app's process, so a client
    /// with no stage has none to move.
    public func pressRPEChip(setIdentity: String, reps: Int, rpe: String) throws -> RPEChipPressReport {
        let session = workout.currentSession
        let focus = ActiveSetFocusManager(session: session)
        switch LockScreenPress.decision(setIdentity: setIdentity, reps: reps, rpe: rpe, session: session, focus: focus) {
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
        guard case .ready(let offer) = press else { return nil }
        self.init(
            repChoices: offer.repChoices,
            prescribedReps: offer.prescribedReps,
            rpeChoices: offer.rpeChoices,
            prescribedRPE: offer.prescribedRPE,
            setIdentity: offer.setIdentity
        )
    }
}

extension SetAddress {
    fileprivate init?(_ setID: ActiveSetID, in session: Session) {
        guard let address = session.placement.coordinate?.address else { return nil }
        self.init(exercise: ExerciseAddress(session: address, order: setID.exerciseOrder), index: setID.setIndex)
    }
}
