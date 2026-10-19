import Foundation
import Observation

/// Why a transcriber returned no transcript.
enum SetTranscriberError: Error, Equatable, Sendable {
    case microphoneDenied
    /// The device has no on-device speech model for the locale, or its assets would not install.
    case unavailable
    case nothingHeard
    case failed
}

/// Speech-to-text heard while the athlete speaks: the caption, the auto-stop, and the Live
/// Transcript, from `start` until `finish`.
@MainActor
protocol SetTranscriber: AnyObject {
    /// Returns once the microphone is live. `hearing` receives the whole transcript so far each
    /// time it changes, and `recording` the mic's audio at 16 kHz mono, until `finish` or `cancel`
    /// returns. A start that throws leaves nothing listening.
    func start(hearing: @escaping @MainActor (String) -> Void, recording: DictationRecorder) async throws(SetTranscriberError)
    /// Stops listening, even when it throws, and returns the transcripts heard, the most likely
    /// first.
    func finish() async throws(SetTranscriberError) -> [String]
    func cancel() async
}

/// The time hands-free Dictation reads: how long a request to listen waits for the stage, and
/// when the athlete has stopped talking.
@MainActor
protocol ListeningClock: AnyObject {
    /// The time since a fixed origin.
    var now: Duration { get }
    /// Returns at `deadline`, or at once when it has passed.
    func sleep(until deadline: Duration) async
}

@MainActor
final class ContinuousListeningClock: ListeningClock {
    private let origin = ContinuousClock.now

    var now: Duration { ContinuousClock.now - origin }

    func sleep(until deadline: Duration) async {
        try? await Task.sleep(until: origin + deadline, clock: .continuous)
    }
}

/// What the Spoken Set for one Set resolves against.
struct SpokenSetContext: Equatable, Sendable {
    /// What the Set's card shows, which fills what the athlete leaves unsaid.
    let draft: SetLogDraft
    /// The Exercise's nearest earlier structured Set Log in the Session, which "same again" logs.
    let previous: SetLog?
}

extension SpokenSetContext {
    /// A Set as its card first shows it.
    @MainActor
    init(for set: ExerciseSet, history: LastPerformedLookupSnapshot) {
        self.init(for: set, showing: SetLogDraft(prefilling: set, suggestion: LoadSuggestionEngine.suggest(for: set, history: history)))
    }

    /// A Set whose card shows `draft`, which the athlete may have changed.
    @MainActor
    init(for set: ExerciseSet, showing draft: SetLogDraft) {
        self.init(draft: draft, previous: set.earlierSetLogs.first?.setLog)
    }

    /// What a Spoken Set for `set` resolves against on every path, the card's mic or a press with
    /// the phone locked: what the card shows for `set` once it has reported it, the card's first
    /// values otherwise.
    @MainActor
    init(for set: ExerciseSet, shownBy focus: ActiveSetFocusManager, history: LastPerformedLookupSnapshot) {
        if let setID = ActiveSetFocusManager.id(for: set), let draft = focus.cardDraft(for: setID) {
            self.init(for: set, showing: draft)
        } else {
            self.init(for: set, history: history)
        }
    }
}

/// One press of the Active Set Card's mic, from the first word heard to the Spoken Set's outcome.
@MainActor
@Observable
final class SetDictation {
    enum State: Equatable {
        case idle
        /// The press began and the transcriber is not yet listening.
        case preparing(ActiveSetID)
        case listening(ActiveSetID, heard: String)
        /// The press ended and its outcome waits on the engines, for at most the Decision Deadline.
        case deciding(ActiveSetID, heard: String)
        case finished(ActiveSetID, Outcome)
    }

    /// What a press does to its Set. Only `logged` and `skipped` write; `heard` is the top transcript.
    enum Outcome: Equatable, Sendable {
        case logged(SetLog, heard: String)
        case skipped(heard: String)
        /// The values for the card to show, some missing or read from a less likely transcript,
        /// which the athlete logs with a tap.
        case filled(SetLogDraft, heard: String)
        case rejected(Rejection, heard: String)
    }

    enum Rejection: Equatable, Sendable {
        case spokenSet(SpokenSet.Rejection)
        case transcriber(SetTranscriberError)
    }

    /// Why listening with no hand on the mic ended on its own.
    enum StopReason: Equatable, Sendable {
        /// The athlete stopped talking.
        case silence
        /// Listening ran as long as it may.
        case cap
        /// Listening ran as long as it may without hearing a word.
        case nothingHeard
    }

    /// The next step of listening with no hand on the mic.
    enum AutoStop: Equatable, Sendable {
        case wake(at: Duration)
        case stop(StopReason)
    }

    /// How long after the last word heard hands-free listening ends.
    nonisolated static let silenceWindow: Duration = .milliseconds(1200)
    /// The longest hands-free listening runs, counted from when the mic went live.
    nonisolated static let listeningCap: Duration = .seconds(8)
    /// How long after a press ends its outcome may wait for the Recording Transcript, the live
    /// engine's finalize included. A safety bound, not the target: a press should decide within
    /// `latencyTarget`.
    nonisolated static let decisionDeadline: Duration = .milliseconds(1500)
    /// How long a press should take to decide once it ends, which each press is measured against.
    nonisolated static let latencyTarget: Duration = .milliseconds(500)

    private(set) var state: State = .idle
    @ObservationIgnored private let transcriber: any SetTranscriber
    @ObservationIgnored private let reader: any RecordingTranscriber
    @ObservationIgnored private let clock: any ListeningClock
    /// Nil means no press is in flight; `finish` and `cancel` take it.
    @ObservationIgnored private var press: Press?

    init(transcriber: any SetTranscriber, reader: any RecordingTranscriber, clock: any ListeningClock = ContinuousListeningClock()) {
        self.transcriber = transcriber
        self.reader = reader
        self.clock = clock
    }

    /// One press of the mic, from `start` until `finish` or `cancel` takes it.
    private struct Press {
        let set: ActiveSetID
        let recorder: DictationRecorder
        let starting: Task<SetTranscriberError?, Never>
        var timeline: PressTimeline
    }

    /// Ignored, returning false, while another press is in flight, so one transcriber never
    /// listens twice.
    @discardableResult
    func start(for set: ActiveSetID) -> Bool {
        guard press == nil, state.pressSetID == nil else { return false }
        state = .preparing(set)
        reader.expectRecording()
        let transcriber = transcriber
        let recorder = DictationRecorder()
        let starting = Task<SetTranscriberError?, Never> { [weak self] in
            do throws(SetTranscriberError) {
                try await transcriber.start(hearing: { [weak self] heard in self?.hear(heard, for: set) }, recording: recorder)
                self?.hear(nil, for: set)
                return nil
            } catch {
                return error
            }
        }
        press = Press(set: set, recorder: recorder, starting: starting, timeline: PressTimeline())
        return true
    }

    /// Listens for `set` with no hand on the mic until the athlete stops talking, then finishes as
    /// a release would. Nothing heard by the cap writes nothing. A tap that finishes the press
    /// first, or a cancel, leaves this nil, as does a press already in flight.
    func listenUntilQuiet(for set: ActiveSetID, in context: () -> SpokenSetContext) async -> Outcome? {
        guard start(for: set), let starting = press?.starting else { return nil }
        guard await starting.value == nil else { return await finish(for: set, in: context()) }
        return await listen(through: starting, for: set, in: context)
    }

    private func listen(
        through starting: Task<SetTranscriberError?, Never>,
        for set: ActiveSetID,
        in context: () -> SpokenSetContext
    ) async -> Outcome? {
        while let timeline = timeline(of: starting), let wentLiveAt = timeline.wentLiveAt {
            switch Self.autoStop(at: clock.now, liveAt: wentLiveAt, lastHeardAt: timeline.lastHeardAt) {
            case .wake(let deadline): await clock.sleep(until: deadline)
            case .stop(.nothingHeard): return await giveUpHearingNothing(for: set)
            case .stop(.silence), .stop(.cap): return await finish(for: set, in: context())
            }
        }
        return nil
    }

    /// The timeline of the press `starting` began, nil once `finish` or `cancel` took it.
    private func timeline(of starting: Task<SetTranscriberError?, Never>) -> PressTimeline? {
        guard let press, press.starting == starting else { return nil }
        return press.timeline
    }

    /// Hands-free listening stops at the first of `silenceWindow` after the last word and
    /// `listeningCap` after the mic went live. With nothing heard yet it looks again a silence
    /// window on, so a first word heard in between still stops a window after it.
    nonisolated static func autoStop(at now: Duration, liveAt: Duration, lastHeardAt: Duration?) -> AutoStop {
        let cap = liveAt + listeningCap
        guard let lastHeardAt else { return now >= cap ? .stop(.nothingHeard) : .wake(at: min(now + silenceWindow, cap)) }
        let quiet = lastHeardAt + silenceWindow
        if quiet <= cap, now >= quiet { return .stop(.silence) }
        return now >= cap ? .stop(.cap) : .wake(at: min(quiet, cap))
    }

    private func giveUpHearingNothing(for set: ActiveSetID) async -> Outcome {
        press = nil
        await transcriber.cancel()
        let outcome = Outcome.rejected(.transcriber(.nothingHeard), heard: "")
        state = .finished(set, outcome)
        return outcome
    }

    /// Waits for the transcriber to start if it has not, so a release during `preparing` still
    /// finishes. Nil when no press for `set` is in flight.
    func finish(for set: ActiveSetID, in context: SpokenSetContext) async -> Outcome? {
        guard let press, press.set == set else { return nil }
        self.press = nil
        let outcome: Outcome
        if let error = await press.starting.value {
            outcome = .rejected(.transcriber(error), heard: "")
        } else {
            outcome = await decide(press, in: context)
        }
        state = .finished(set, outcome)
        return outcome
    }

    /// Closes the recording and has the recording engine read it the instant the press ends,
    /// alongside the live engine's finalize, then decides at the first of both answers and the
    /// Decision Deadline. A Recording Transcript still being read at the deadline is dropped.
    private func decide(_ press: Press, in context: SpokenSetContext) async -> Outcome {
        let deadline = clock.now + Self.decisionDeadline
        let reading = Reading(of: press.recorder.close(), by: reader)
        state = .deciding(press.set, heard: state.heard)
        let live: LiveHearing
        do throws(SetTranscriberError) {
            live = .transcripts(try await transcriber.finish())
        } catch {
            live = .failed(error, caption: state.heard)
        }
        let decode = await reading.decode(by: deadline, on: clock)
        return Self.decision(of: Hearing(live: live, recording: decode.transcript), in: context).outcome
    }

    /// Stops a press that has not begun finishing, writing nothing. The press stays in flight
    /// until the transcriber stops, so the next one cannot start under it.
    func cancel() async {
        guard let press else { return }
        self.press = nil
        _ = await press.starting.value
        await transcriber.cancel()
        state = .idle
    }

    func dismiss() {
        guard case .finished = state else { return }
        state = .idle
    }

    /// `heard` nil is the transcriber going live.
    private func hear(_ heard: String?, for set: ActiveSetID) {
        guard state.pressSetID == set else { return }
        guard let heard else {
            press?.timeline.wentLiveAt = clock.now
            state = .listening(set, heard: state.heard)
            return
        }
        if !heard.isEmpty, heard != state.heard { press?.timeline.lastHeardAt = clock.now }
        state = state.hearing(heard)
    }
}

/// When a press's events happened, on the press's clock. Auto-stop reads it.
struct PressTimeline: Equatable, Sendable {
    var wentLiveAt: Duration?
    var lastHeardAt: Duration?
}

extension SetDictation {
    /// One press's recording being read by the recording engine, off the main actor, from the
    /// instant the press ends. Nothing recorded is never read.
    @MainActor
    final class Reading {
        private var decoding: Task<RecordingDecode, Never>?
        private var arrived: RecordingDecode?

        init(of recording: DictationRecording, by reader: any RecordingTranscriber) {
            guard !recording.samples.isEmpty else { return }
            decoding = Task { @MainActor [weak self] in
                let decode = await reader.transcribe(recording)
                self?.arrived = decode
                return decode
            }
        }

        /// The decode once it is in, or `late` at `deadline` on `clock`, which cancels the read. One
        /// already in decides whatever the clock says.
        func decode(by deadline: Duration, on clock: any ListeningClock) async -> RecordingDecode {
            guard let decoding else { return .missing(.nothingRecorded) }
            if let arrived { return arrived }
            guard let decode = await BoundedWait.wait(for: decoding, until: deadline, on: clock) else {
                decoding.cancel()
                return .missing(.late)
            }
            return decode
        }
    }
}

extension SetDictation.State {
    /// The Set a press in flight is for, from its start until its outcome.
    var pressSetID: ActiveSetID? {
        switch self {
        case .preparing(let set), .listening(let set, _), .deciding(let set, _): set
        case .idle, .finished: nil
        }
    }

    fileprivate var heard: String {
        switch self {
        case .listening(_, let heard), .deciding(_, let heard): heard
        case .idle, .preparing, .finished: ""
        }
    }

    /// This press captioned `heard`, in the same phase: a caption the live engine delivers as it
    /// finalizes does not put a deciding press back to listening.
    fileprivate func hearing(_ heard: String) -> Self {
        switch self {
        case .preparing(let set), .listening(let set, _): .listening(set, heard: heard)
        case .deciding(let set, _): .deciding(set, heard: heard)
        case .idle, .finished: self
        }
    }
}

/// What the Set card's mic and action capsule show of a press for the card's Set.
enum SetCardDictation: Equatable {
    case ready
    /// The capsule shows what is heard in place of the Log button.
    case listening(caption: String)
    /// The capsule keeps what was heard, with the mic off, until the press's outcome is in.
    case deciding(caption: String)
    /// The capsule shows what was heard, or why nothing was, until the athlete taps it.
    case rejected(caption: String)
    /// The card's values become these, with nothing written.
    case filled(SetLogDraft)

    init(_ state: SetDictation.State, for setID: ActiveSetID) {
        switch state {
        case .preparing(setID), .listening(setID, _): self = .listening(caption: Self.caption(hearing: state.heard))
        case .deciding(setID, let heard): self = .deciding(caption: Self.caption(hearing: heard))
        case .finished(setID, .rejected(let rejection, let heard)): self = .rejected(caption: Self.caption(rejection, heard: heard))
        case .finished(setID, .filled(let values, _)): self = .filled(values)
        case .idle, .preparing, .listening, .deciding, .finished: self = .ready
        }
    }

    /// What the capsule says in place of the Log button; nil leaves the Log button.
    var caption: String? {
        switch self {
        case .listening(let caption), .deciding(let caption), .rejected(let caption): caption
        case .ready, .filled: nil
        }
    }

    var isListening: Bool {
        guard case .listening = self else { return false }
        return true
    }

    private static func caption(hearing heard: String) -> String {
        heard.isEmpty ? "Listening" : heard
    }

    private static func caption(_ rejection: SetDictation.Rejection, heard: String) -> String {
        switch rejection {
        case .transcriber(.microphoneDenied): "Microphone is off in Settings"
        case .transcriber(.unavailable): "Speech isn’t available"
        case .spokenSet(.nothingHeard), .transcriber(.nothingHeard): "Nothing heard"
        case .spokenSet, .transcriber(.failed): rejection.readback(of: heard)
        }
    }
}

extension SetDictation.Rejection {
    /// What the card and the Live Activity say of a rejected transcript: the words heard, and for a
    /// Set no lifter logs, an ask to say it again.
    func readback(of heard: String) -> String {
        guard !heard.isEmpty else { return "Nothing heard" }
        guard case .spokenSet(.implausible) = self else { return "“\(heard)”" }
        return "“\(heard)”, say it again"
    }
}

extension SetDictation {
    /// The mic's press, as a weight step answers a tap.
    nonisolated static let startHaptic = Haptic.input(Theme.Haptics.stepperTick)
}

extension SetDictation.Outcome {
    /// A write feels like the tap it stands in for; anything the athlete still has to act on warns.
    var haptic: Haptic {
        switch self {
        case .logged: .input(Theme.Haptics.logTap)
        case .skipped: .input(Theme.Haptics.skipDud)
        case .filled, .rejected: .warning
        }
    }
}
