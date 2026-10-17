import Foundation

/// The Live Activity a headless Dictation reads back on. The app's ActivityKit adapter conforms.
@MainActor
protocol DictationLiveActivityAdapter: AnyObject {
    /// Shows `content`, starting a Live Activity for the Set when none is up. Returns once it
    /// shows, because the system stops a recording that has no Live Activity up.
    func show(_ content: LiveActivityDictationContent, sessionLabel: String) async
    /// Shows why there was no Set to listen for, over a running rest when one is up.
    func show(_ noSet: LiveActivityNoSetReadback) async
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
    }

    enum NoSet: Equatable, Sendable {
        case noCurrentSession
        case everythingLogged
        /// The card's mic is listening, so the Set is the card's.
        case micBusy
    }

    /// How long the flush may hold the run after the result shows. A flush still going runs on,
    /// and a write that never lands stays queued for the next foreground (ADR-0006).
    nonisolated static let flushWait: Duration = .seconds(10)

    private let app: WorkoutApplication
    private let dictation: SetDictation
    /// The stage's focus, so this listens on the Set the card shows and moves the card past it.
    private let focus: ActiveSetFocusManager
    private let liveActivity: any DictationLiveActivityAdapter
    private let signIn: any SignInRestoring
    private let clock: any ListeningClock
    private let now: () -> Date
    /// Held so the flush outlives `flushWait`; nil until a write asks for one.
    private(set) var flushing: Task<FlushReport?, Never>?
    private let flushWait = BoundedWait()

    init(
        app: WorkoutApplication,
        dictation: SetDictation,
        focus: ActiveSetFocusManager,
        liveActivity: any DictationLiveActivityAdapter,
        signIn: any SignInRestoring,
        clock: any ListeningClock,
        now: @escaping () -> Date
    ) {
        self.app = app
        self.dictation = dictation
        self.focus = focus
        self.liveActivity = liveActivity
        self.signIn = signIn
        self.clock = clock
        self.now = now
    }

    func run() async -> Outcome {
        guard let session = app.workout.currentSession else {
            await liveActivity.show(.noCurrentSession)
            return .noSetToLog(.noCurrentSession)
        }
        guard let position = focus.activeSet(in: session) else {
            await liveActivity.show(.noSetLeft(session: session.liveActivityLabel))
            return .noSetToLog(.everythingLogged)
        }
        guard dictation.state.listeningSetID == nil else { return .noSetToLog(.micBusy) }
        let shown = LiveActivitySetContent(position)
        let label = session.liveActivityLabel
        await liveActivity.show(LiveActivityDictationContent(readback: .listening, subject: .set(shown)), sessionLabel: label)
        let set = position.set
        let history = app.lastPerformed.snapshot
        guard let heard = await dictation.listenUntilQuiet(for: position.setID, in: { SpokenSetContext(for: set, history: history) }) else {
            return .noSetToLog(.micBusy)
        }
        let settled = settle(heard, for: position, in: session, shown: shown)
        await liveActivity.show(settled.content, sessionLabel: label)
        guard settled.wrote else { return settled.outcome }
        focus.advanceAfterSpokenWrite(position.set, in: session, holding: false)
        dictation.dismiss()
        await flush()
        return settled.outcome
    }

    private struct Settled {
        let outcome: Outcome
        let content: LiveActivityDictationContent
        let wrote: Bool
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
        return settled(heard, for: position, in: session, shown: shown, wasSupersetMember: wasSupersetMember)
    }

    private func settled(
        _ heard: SetDictation.Outcome,
        for position: SessionSetPosition,
        in session: Session,
        shown: LiveActivitySetContent,
        wasSupersetMember: Bool
    ) -> Settled {
        let setID = position.setID
        switch heard {
        case .logged(let setLog, _):
            return Settled(
                outcome: .logged(setLog, at: setID),
                content: LiveActivityDictationContent(
                    readback: .logged(setLog.readback),
                    subject: restSubject(afterLogging: position.set, in: session, wasSupersetMember: wasSupersetMember, else: shown)
                ),
                wrote: true
            )
        case .skipped:
            return Settled(
                outcome: .skipped(at: setID),
                content: LiveActivityDictationContent(readback: .skipped, subject: .set(shown)),
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

    /// The rest the stage would start after this Set, toward the Set it would focus next. With no
    /// rest to start, the Set that was logged.
    private func restSubject(
        afterLogging set: ExerciseSet,
        in session: Session,
        wasSupersetMember: Bool,
        else shown: LiveActivitySetContent
    ) -> LiveActivityDictationContent.Subject {
        let kind = RestTriggerPolicy.restKind(afterLogging: set, in: session, isSupersetMember: wasSupersetMember, isRestRunning: false)
        guard let kind else { return .set(shown) }
        let start = now()
        let duration =
            switch kind {
            case .standard: app.settings.standardRestDuration
            case .superset: app.settings.supersetRestDuration
            }
        let content = focus.liveActivityRestContent(
            afterLogging: set,
            in: session,
            restStartDate: start,
            restEndDate: start.addingTimeInterval(duration.timeInterval)
        )
        guard let content else { return .set(shown) }
        return .rest(content)
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
