import Foundation

/// The Live Activity a headless Dictation reads back on. The app's ActivityKit adapter conforms.
@MainActor
protocol DictationLiveActivityAdapter: AnyObject {
    /// Shows `content`, starting a Live Activity for the Set when none is up. Returns once it
    /// shows, because the system stops a recording that has no Live Activity up, and false when no
    /// Live Activity shows it, as when the athlete turned them off for the app.
    @discardableResult
    func show(_ content: LiveActivityDictationContent, sessionLabel: String) async -> Bool
    /// Shows why there was no Set to listen for, over a running rest when one is up.
    func show(_ noSet: LiveActivityNoSetReadback) async
    /// Takes the readback off once the card has the Set: a Live Activity started for it ends now,
    /// and a rest it rode on shows as the stage left it.
    func withdrawReadback() async
}

/// Restores the Google sign-in that a launch with no scene never did.
@MainActor
protocol SignInRestoring: AnyObject {
    func restorePreviousSignIn() async -> Bool
}

/// A Dictation run from the Action button, a control, or Siri with the app closed or the phone
/// locked. It listens for the Current Session's active Set, the one the card would, writes through
/// the facade, reads back on the Live Activity, and flushes. Every decision lives here; the intent
/// only runs it.
@MainActor
final class BackgroundDictation {
    enum Outcome: Equatable, Sendable {
        case logged(SetLog, at: ActiveSetID)
        case skipped(at: ActiveSetID)
        case notLogged(NotLogged, at: ActiveSetID)
        case noSetToLog(NoSet)
        /// Nothing listened: no Live Activity could show the recording, which a recording with the
        /// app behind must have.
        case liveActivitiesOff
    }

    /// Why a press did nothing, in the athlete's words, for the surface that pressed to show.
    enum Refused: Error, LocalizedError, Equatable, Sendable {
        case liveActivitiesOff

        var errorDescription: String? {
            switch self {
            case .liveActivitiesOff: "Turn on Live Activities for WorkoutTracker to log while locked"
            }
        }
    }

    /// Listened, and wrote nothing.
    enum NotLogged: Equatable, Sendable {
        /// A value was not said and the card does not hold it.
        case missingValues(SetLogDraft, heard: String)
        /// Only a less likely transcript read a Set: the guess the card would show, which no card can.
        case ambiguous(heard: String)
        case rejected(SetDictation.Rejection, heard: String)
        /// The store refused the write.
        case writeFailed
        /// While this listened, the Set was logged or skipped elsewhere, or a sync replaced the
        /// Session, so what was heard has no Set to go to.
        case setChanged
    }

    enum NoSet: Equatable, Sendable {
        case noCurrentSession
        case everythingLogged
        /// The card's mic is listening, or took the press from this one, so the Set is the card's.
        case micBusy
    }

    /// How long the flush may hold the run after the result shows. A flush still going runs on,
    /// and a write that never lands stays queued for the next foreground (ADR-0006).
    nonisolated static let flushWait: Duration = .seconds(10)

    private let app: WorkoutApplication
    private let dictation: SetDictation
    /// The stage's focus, so this listens on the Set the card shows and moves the card past it.
    private let focus: ActiveSetFocusManager
    /// The process's one rest, which a write here starts as the stage would: its pill, the Live
    /// Activity, and the rest-end notification all read it.
    private let restTimer: RestTimer
    private let liveActivity: any DictationLiveActivityAdapter
    private let signIn: any SignInRestoring
    private let clock: any ListeningClock
    /// Held so the flush outlives `flushWait`; nil until a write asks for one.
    private(set) var flushing: Task<FlushReport?, Never>?
    private let flushWait = BoundedWait()

    init(
        app: WorkoutApplication,
        dictation: SetDictation,
        focus: ActiveSetFocusManager,
        restTimer: RestTimer,
        liveActivity: any DictationLiveActivityAdapter,
        signIn: any SignInRestoring,
        clock: any ListeningClock
    ) {
        self.app = app
        self.dictation = dictation
        self.focus = focus
        self.restTimer = restTimer
        self.liveActivity = liveActivity
        self.signIn = signIn
        self.clock = clock
    }

    func run() async -> Outcome {
        let (position, session): (SessionSetPosition, Session)
        switch await target() {
        case .noSet(let outcome): return outcome
        case .set(let target, let current): (position, session) = (target, current)
        }
        let shown = LiveActivitySetContent(position)
        let label = session.liveActivityLabel
        let listening = LiveActivityDictationContent(readback: .listening, subject: .set(shown))
        guard await liveActivity.show(listening, sessionLabel: label) else { return .liveActivitiesOff }
        switch await listen(for: position, in: session, shown: shown) {
        case .withdrawn(let outcome):
            await liveActivity.withdrawReadback()
            return outcome
        case .settled(let settled):
            return await readBack(settled, sessionLabel: label)
        }
    }

    /// The result replaces "Listening…", and a write flushes once it shows.
    private func readBack(_ settled: Settled, sessionLabel: String) async -> Outcome {
        await liveActivity.show(settled.content, sessionLabel: sessionLabel)
        if settled.wrote {
            await flush()
        }
        return settled.outcome
    }

    private enum Target {
        case set(SessionSetPosition, in: Session)
        case noSet(Outcome)
    }

    /// The Set to listen for. A press with none says why on the Live Activity, unless the card's
    /// mic is listening, which the card shows itself.
    private func target() async -> Target {
        guard let session = app.workout.currentSession else {
            await liveActivity.show(.noCurrentSession)
            return .noSet(.noSetToLog(.noCurrentSession))
        }
        // The card keeps a Set its mic wrote for the athlete to glance at and undo. A press with
        // the phone locked says they have moved on, so the hold ends as a touch of the card would,
        // and no card stays held while another Set is written.
        focus.endHoldAfterSpokenWrite()
        guard let position = focus.activeSet(in: session) else {
            await liveActivity.show(.noSetLeft(session: session.liveActivityLabel))
            return .noSet(.noSetToLog(.everythingLogged))
        }
        guard dictation.state.listeningSetID == nil else { return .noSet(.noSetToLog(.micBusy)) }
        return .set(position, in: session)
    }

    /// How a press ends once "Listening…" shows. Every end replaces it: a result reads back, and
    /// a press the card took withdraws the readback.
    private enum Ending {
        case settled(Settled)
        case withdrawn(Outcome)
    }

    private struct Settled {
        let outcome: Outcome
        let content: LiveActivityDictationContent
        let wrote: Bool
    }

    private func listen(for position: SessionSetPosition, in session: Session, shown: LiveActivitySetContent) async -> Ending {
        let set = position.set
        let history = app.lastPerformed.snapshot
        let context = { [focus] in SpokenSetContext(for: set, shownBy: focus, history: history) }
        guard let heard = await dictation.listenUntilQuiet(for: position.setID, in: context) else {
            return .withdrawn(.noSetToLog(.micBusy))
        }
        // The card refuses a write to a Set no longer Pending once the transcript is in; so does this.
        guard app.workout.currentSession === session, set.isPending else {
            dictation.dismiss()
            return .settled(Self.notLogged(.setChanged, at: position.setID, shown: shown))
        }
        return .settled(settle(heard, for: position, in: session, shown: shown))
    }

    private func settle(
        _ heard: SetDictation.Outcome,
        for position: SessionSetPosition,
        in session: Session,
        shown: LiveActivitySetContent
    ) -> Settled {
        // Read before the write, which dissolves a Superset when it logs a side's last Set.
        let wasSupersetMember = focus.isPaired(position.exercise)
        do {
            try app.write(heard, to: position.set)
        } catch {
            return Self.notLogged(.writeFailed, at: position.setID, shown: shown)
        }
        let settled = settled(heard, for: position, in: session, shown: shown, wasSupersetMember: wasSupersetMember)
        // The card moves on with the write, in the stage's order (write, rest, then focus) and
        // before anything is awaited, since a second press can arrive while the readback draws.
        if settled.wrote {
            focus.advanceAfterSpokenWrite(position.set, in: session, holding: false)
            dictation.dismiss()
        }
        return settled
    }

    private func settled(
        _ heard: SetDictation.Outcome,
        for position: SessionSetPosition,
        in session: Session,
        shown: LiveActivitySetContent,
        wasSupersetMember: Bool
    ) -> Settled {
        let setID = position.setID
        let written = LiveActivityDictationContent.WrittenSet(position, in: session)
        switch heard {
        case .logged(let setLog, _):
            return Settled(
                outcome: .logged(setLog, at: setID),
                content: LiveActivityDictationContent(
                    readback: .logged(setLog.readback, to: written),
                    subject: restSubject(afterLogging: position, in: session, wasSupersetMember: wasSupersetMember)
                ),
                wrote: true
            )
        case .skipped:
            return Settled(
                outcome: .skipped(at: setID),
                content: LiveActivityDictationContent(readback: .skipped(written), subject: .set(LiveActivitySetContent(position))),
                wrote: true
            )
        case .filled(let values, let heard):
            return Self.notLogged(NotLogged(filled: values, heard: heard), at: setID, shown: shown)
        case .rejected(let rejection, let heard):
            return Self.notLogged(.rejected(rejection, heard: heard), at: setID, shown: shown)
        }
    }

    private static func notLogged(_ why: NotLogged, at setID: ActiveSetID, shown: LiveActivitySetContent) -> Settled {
        Settled(
            outcome: .notLogged(why, at: setID),
            content: LiveActivityDictationContent(readback: .notLogged(why.caption), subject: .set(shown)),
            wrote: false
        )
    }

    /// Starts the rest the stage would after this Set, on the stage's own timer, and reads it back
    /// toward the Set the card focuses next. With no rest to start, the logged Set's Exercise as it
    /// now stands.
    private func restSubject(
        afterLogging position: SessionSetPosition,
        in session: Session,
        wasSupersetMember: Bool
    ) -> LiveActivityDictationContent.Subject {
        let set = position.set
        let kind = RestTriggerPolicy.restKind(
            afterLogging: set,
            in: session,
            isSupersetMember: wasSupersetMember,
            isRestRunning: restTimer.isRunning
        )
        guard let kind else { return .set(LiveActivitySetContent(position)) }
        restTimer.start(
            duration: restDuration(kind).timeInterval,
            origin: position.setID,
            originSetObjectID: ObjectIdentifier(set),
            kind: kind
        )
        let content = restTimer.interval.flatMap { interval in
            focus.liveActivityRestContent(afterLogging: set, in: session, restStartDate: interval.start, restEndDate: interval.end)
        }
        guard let content else { return .set(LiveActivitySetContent(position)) }
        return .rest(content)
    }

    private func restDuration(_ kind: RestKind) -> RestDurationSetting {
        switch kind {
        case .standard: app.settings.standardRestDuration
        case .superset: app.settings.supersetRestDuration
        }
    }

    /// Restores the sign-in when no scene has, then flushes for at most `flushWait`.
    private func flush() async {
        if !app.settings.isSignedIn, await signIn.restorePreviousSignIn() {
            app.settings.isSignedIn = true
        }
        let flushing = Task { @MainActor [app] in try? await app.flush() }
        self.flushing = flushing
        await flushWait.wait(for: flushing, until: clock.now + Self.flushWait, on: clock)
    }
}

extension BackgroundDictation.Outcome {
    /// What the intent throws for the surface that pressed to show; nil when the press ran.
    var refusal: BackgroundDictation.Refused? {
        guard case .liveActivitiesOff = self else { return nil }
        return .liveActivitiesOff
    }
}

extension BackgroundDictation.NotLogged {
    /// The values the card would fill for a tap, which no card can: `ambiguous` once complete.
    init(filled values: SetLogDraft, heard: String) {
        self = values.missingFields.isEmpty ? .ambiguous(heard: heard) : .missingValues(values, heard: heard)
    }

    /// What the Live Activity says in place of a Set Log.
    var caption: String {
        switch self {
        case .missingValues(let values, let heard):
            let missing = SetLogDraft.Field.allCases.filter(values.missingFields.contains).map(\.spokenName)
            return "\(Self.quoted(heard)), no \(missing.joined(separator: " or "))"
        case .ambiguous(let heard):
            return Self.quoted(heard)
        case .rejected(let rejection, let heard):
            return Self.caption(rejection, heard: heard)
        case .writeFailed:
            return "Couldn’t save. Unlock to log"
        case .setChanged:
            return "The Set changed while listening"
        }
    }

    private static func caption(_ rejection: SetDictation.Rejection, heard: String) -> String {
        switch rejection {
        case .transcriber(.microphoneDenied), .transcriber(.unavailable): "Open WorkoutTracker once to allow the mic"
        case .transcriber(.failed): "Couldn’t listen. Unlock to log"
        case .spokenSet(.nothingHeard), .transcriber(.nothingHeard): "Nothing heard"
        case .spokenSet: quoted(heard)
        }
    }

    private static func quoted(_ heard: String) -> String {
        heard.isEmpty ? "Nothing heard" : "“\(heard)”"
    }
}

extension SetLogDraft.Field {
    fileprivate var spokenName: String {
        switch self {
        case .weight: "weight"
        case .reps: "reps"
        case .rpe: "RPE"
        }
    }
}

/// Waits for an operation or a deadline, whichever comes first, and lets the operation run on.
@MainActor
final class BoundedWait {
    private var waiting: CheckedContinuation<Void, Never>?
    private var operationWatch: Task<Void, Never>?
    private var deadlineWatch: Task<Void, Never>?

    func wait<Value: Sendable>(for operation: Task<Value, Never>, until deadline: Duration, on clock: any ListeningClock) async {
        await withCheckedContinuation { continuation in
            waiting = continuation
            operationWatch = Task { @MainActor [weak self] in
                _ = await operation.value
                self?.finish()
            }
            deadlineWatch = Task { @MainActor [weak self] in
                await clock.sleep(until: deadline)
                self?.finish()
            }
        }
    }

    private func finish() {
        let waiting = waiting
        self.waiting = nil
        waiting?.resume()
    }
}
