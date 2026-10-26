import Foundation
import Observation
import os

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

    /// Where a press came from: the card's mic, held or listening hands-free with the app on
    /// screen, or a press that runs headless.
    enum Surface: String, Codable, Sendable {
        case card, headless
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

    /// How long after a press ends its outcome may wait for the Recording Transcript, the live
    /// engine's finalize included. A safety bound, not the target: a press should decide within
    /// `latencyTarget`.
    nonisolated static let decisionDeadline: Duration = .milliseconds(1500)
    /// How long a press should take to decide once it ends, which each press is measured against.
    nonisolated static let latencyTarget: Duration = .milliseconds(500)

    private(set) var state: State = .idle
    @ObservationIgnored private let transcriber: any SetTranscriber
    @ObservationIgnored private let reader: any RecordingTranscriber
    @ObservationIgnored private let journal: DictationJournal
    @ObservationIgnored private let clock: any ListeningClock
    @ObservationIgnored private let decisionDeadline: Duration
    /// Nil means no press is in flight; `finish` and `cancel` take it.
    @ObservationIgnored private var press: Press?

    /// Instruments shows a press's phases as intervals beside the main thread's hangs.
    static let signposter = OSSignposter(subsystem: "WorkoutTracker", category: "Dictation")

    init(
        transcriber: any SetTranscriber,
        reader: any RecordingTranscriber,
        journal: DictationJournal,
        clock: any ListeningClock = ContinuousListeningClock(),
        decisionDeadline: Duration = SetDictation.decisionDeadline
    ) {
        self.transcriber = transcriber
        self.reader = reader
        self.journal = journal
        self.clock = clock
        self.decisionDeadline = decisionDeadline
    }

    /// One press of the mic, from `start` until `finish` or `cancel` takes it.
    private struct Press {
        let id = UUID()
        let set: ActiveSetID
        let surface: Surface
        let pressedAt: Date
        let modelAtPress: SpeechModelState
        let recorder: DictationRecorder
        let starting: Task<SetTranscriberStartError?, Never>
        let watchdog = MainThreadWatchdog()
        let signpost: OSSignpostIntervalState
        var timeline: PressTimeline
        var startRefusal: MicStartRefusal?
        var voice = VoiceActivity()
        /// The latest read of the recording so far, asked at a Pause while listening hands-free.
        var earlyRead: Reading?

        /// The early read, when a press that stopped on its own can decide with it: it is still
        /// reading or heard a transcript, and the athlete said nothing after the audio it read.
        @MainActor func earlyReadOfAllTheSpeech(endedBy end: DictationRecord.PressEnd) -> Reading? {
            guard end != .released, let earlyRead, earlyRead.isWorthKeeping, voice.isPaused(since: earlyRead.recording.samples.count)
            else { return nil }
            return earlyRead
        }
    }

    /// A press of the card's mic. Ignored, returning false, while another press is in flight, so
    /// one transcriber never listens twice.
    @discardableResult
    func start(for set: ActiveSetID) -> Bool {
        start(for: set, on: .card)
    }

    private func start(for set: ActiveSetID, on surface: Surface) -> Bool {
        guard press == nil, state.pressSetID == nil else { return false }
        state = .preparing(set)
        let modelAtPress = reader.readiness
        reader.expectRecording()
        let transcriber = transcriber
        let recorder = DictationRecorder()
        let starting = Task<SetTranscriberStartError?, Never> { [weak self] in
            do throws(SetTranscriberStartError) {
                try await transcriber.start(hearing: { [weak self] heard in self?.hear(heard, for: set) }, recording: recorder)
                self?.hear(nil, for: set)
                return nil
            } catch {
                return error
            }
        }
        press = Press(
            set: set,
            surface: surface,
            pressedAt: clock.date,
            modelAtPress: modelAtPress,
            recorder: recorder,
            starting: starting,
            signpost: Self.signposter.beginInterval("Press"),
            timeline: PressTimeline(pressedAt: clock.now)
        )
        return true
    }

    /// Listens for `set` with no hand on the mic until the athlete stops talking, then finishes as
    /// a release would. Nothing heard by the cap writes nothing. A tap that finishes the press
    /// first, or a cancel, leaves this nil, as does a press already in flight.
    func listenUntilQuiet(for set: ActiveSetID, on surface: Surface, in context: () -> SpokenSetContext) async -> Outcome? {
        guard start(for: set, on: surface), let starting = press?.starting else { return nil }
        guard await starting.value == nil else { return await finish(for: set, in: context(), ending: .unstarted) }
        return await listen(through: starting, for: set, in: context)
    }

    private func listen(
        through starting: Task<SetTranscriberStartError?, Never>,
        for set: ActiveSetID,
        in context: () -> SpokenSetContext
    ) async -> Outcome? {
        while let step = nextStep(of: starting, in: context) {
            switch step {
            case .wake(let deadline): await wake(at: deadline)
            case .read: readSoFar()
            case .stop(.nothingHeard): return await giveUpHearingNothing(for: set, in: context())
            case .stop(let reason): return await finish(for: set, in: context(), ending: DictationRecord.PressEnd(reason))
            }
        }
        return nil
    }

    /// The next step of the press `starting` began, with the mic levels recorded since the last;
    /// nil once `finish` or `cancel` took it.
    private func nextStep(of starting: Task<SetTranscriberStartError?, Never>, in context: () -> SpokenSetContext) -> AutoStop? {
        guard var press, press.starting == starting, let wentLiveAt = press.timeline.wentLiveAt else { return nil }
        press.voice.hear(press.recorder.levels(from: press.voice.frames))
        self.press = press
        let earlyRead = press.earlyRead.map { reading in
            HandsFreeEarlyRead(samples: reading.recording.samples.count, heard: reading.arrived.map { Self.heard($0, in: context()) })
        }
        return Self.autoStop(
            at: clock.now,
            liveAt: wentLiveAt,
            lastHeardAt: press.timeline.lastHeardAt,
            voice: press.voice,
            earlyRead: earlyRead
        )
    }

    /// Sleeps until `deadline`, or until an early read in flight comes in.
    private func wake(at deadline: Duration) async {
        guard let reading = press?.earlyRead, reading.isReading else { return await clock.sleep(until: deadline) }
        await reading.arrival(until: deadline, on: clock)
    }

    /// One read in flight at a time: a newer Pause's read replaces an older one's.
    private func readSoFar() {
        guard var press else { return }
        press.earlyRead?.cancel()
        press.earlyRead = Reading(of: press.recorder.snapshot(), by: reader, on: clock)
        press.timeline.earlyReadAskedAt = clock.now
        self.press = press
    }

    /// No transcript to read, so the recording engine is not asked.
    private func giveUpHearingNothing(for set: ActiveSetID, in context: SpokenSetContext) async -> Outcome? {
        guard var press else { return nil }
        self.press = nil
        press.timeline.endedAt = clock.now
        await transcriber.cancel()
        let unasked = recording(.missing(.notAsked), of: press.recorder.close(), for: press)
        let outcome = decided(press, .nothingHeard, live: .failed(.nothingHeard, caption: ""), recording: unasked, in: context)
        state = .finished(set, outcome)
        return outcome
    }

    /// Waits for the transcriber to start if it has not, so a release during `preparing` still
    /// finishes. Nil when no press for `set` is in flight.
    func finish(for set: ActiveSetID, in context: SpokenSetContext) async -> Outcome? {
        await finish(for: set, in: context, ending: .released)
    }

    private func finish(for set: ActiveSetID, in context: SpokenSetContext, ending end: DictationRecord.PressEnd) async -> Outcome? {
        guard var press, press.set == set else { return nil }
        self.press = nil
        press.timeline.endedAt = clock.now
        let deciding = Self.signposter.beginInterval("Deciding")
        let outcome: Outcome
        if let error = await press.starting.value {
            press.startRefusal = error.refusal
            let unasked = recording(.missing(.notAsked), of: press.recorder.close(), for: press)
            outcome = decided(press, end, live: .failed(error.reason, caption: ""), recording: unasked, in: context)
        } else {
            outcome = await decide(press, end, in: context)
        }
        Self.signposter.endInterval("Deciding", deciding)
        state = .finished(set, outcome)
        return outcome
    }

    /// Closes the recording and has the recording engine read it the instant the press ends,
    /// alongside the live engine's finalize, then decides at the first of both answers and the
    /// Decision Deadline. A Recording Transcript still being read at the deadline is dropped.
    /// Listening hands-free, an early read of all the athlete said stands in for that read.
    private func decide(_ press: Press, _ end: DictationRecord.PressEnd, in context: SpokenSetContext) async -> Outcome {
        var press = press
        // A release before the live engine went live took the press before `hear` could stamp it.
        press.timeline.wentLiveAt = press.timeline.wentLiveAt ?? clock.now
        let deadline = clock.now + decisionDeadline
        let recording = press.recorder.close()
        press.voice.hear(press.recorder.levels(from: press.voice.frames))
        let reading: Reading
        if let early = press.earlyReadOfAllTheSpeech(endedBy: end) {
            reading = early
        } else {
            press.earlyRead?.cancel()
            reading = Reading(of: recording, by: reader, on: clock)
        }
        press.timeline.recordingAskedAt = reading.askedAt
        state = .deciding(press.set, heard: state.heard)
        let finalizing = Self.signposter.beginInterval("LiveFinalize")
        let live: LiveHearing
        do throws(SetTranscriberError) {
            live = .transcripts(try await transcriber.finish())
        } catch {
            live = .failed(error, caption: state.heard)
        }
        Self.signposter.endInterval("LiveFinalize", finalizing)
        press.timeline.liveFinishedAt = clock.now
        let decode = await reading.decode(by: deadline, on: clock)
        press.timeline.recordingReadAt = reading.readAt
        press.timeline.recordingDroppedAt = reading.droppedAt
        return decided(press, end, live: live, recording: self.recording(decode, of: reading.recording, for: press), in: context)
    }

    private func recording(_ decode: RecordingDecode, of recording: DictationRecording, for press: Press) -> DictationRecord.Recording {
        DictationRecord.Recording(modelAtPress: press.modelAtPress, modelAtEnd: reader.readiness, decode: decode, of: recording)
    }

    /// Decides the press under the shipped rule and hands its Dictation Record to the journal.
    private func decided(
        _ press: Press,
        _ end: DictationRecord.PressEnd,
        live: LiveHearing,
        recording: DictationRecord.Recording,
        in context: SpokenSetContext
    ) -> Outcome {
        var press = press
        let hearing = Hearing(live: live, recording: recording.result.transcript)
        let decision = Self.decision(of: hearing, in: context)
        press.timeline.decidedAt = clock.now
        let decided = DictationRecord.Decided(
            end: end,
            set: context,
            live: DictationRecord.Live(live, captionChanges: press.timeline.captionChanges, startRefusal: press.startRefusal),
            recording: recording,
            decision: DictationRecord.Decision(decision, of: hearing, in: context)
        )
        keep(press, .decided(decided))
        return decision.outcome
    }

    /// Never awaits: the journal writes off the main actor.
    private func keep(_ press: Press, _ ending: DictationRecord.Ending) {
        journal.append(
            DictationRecord(
                id: press.id,
                pressedAt: press.pressedAt,
                app: .current,
                surface: press.surface,
                ending: ending,
                timeline: DictationRecord.Timeline(press.timeline),
                device: .current(),
                longestMainThreadStallMs: press.watchdog.stop().wholeMilliseconds
            )
        )
        Self.signposter.endInterval("Press", press.signpost)
    }

    /// Stops a press that has not begun finishing, writing nothing. The press stays in flight
    /// until the transcriber stops, so the next one cannot start under it.
    func cancel() async {
        guard var press else { return }
        self.press = nil
        press.timeline.endedAt = clock.now
        press.earlyRead?.cancel()
        _ = await press.starting.value
        await transcriber.cancel()
        keep(press, .cancelled)
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
        if !heard.isEmpty, heard != state.heard { press?.timeline.heard(at: clock.now) }
        state = state.hearing(heard)
    }
}

/// When a press's events happened, on the press's clock. Auto-stop reads it, and the press's
/// Dictation Record carries it.
struct PressTimeline: Equatable, Sendable {
    let pressedAt: Duration
    var wentLiveAt: Duration?
    var firstHeardAt: Duration?
    var lastHeardAt: Duration?
    /// How many times the caption changed while the athlete spoke.
    var captionChanges = 0
    /// Nil until the press is released, stops on its own, or is cancelled.
    var endedAt: Duration?
    var liveFinishedAt: Duration?
    /// When the latest read of the recording so far was asked, listening hands-free.
    var earlyReadAskedAt: Duration?
    /// When the read the press was decided with was asked: before `endedAt` for an early read.
    var recordingAskedAt: Duration?
    var recordingReadAt: Duration?
    var recordingDroppedAt: Duration?
    var decidedAt: Duration?

    init(pressedAt: Duration) {
        self.pressedAt = pressedAt
    }

    mutating func heard(at now: Duration) {
        firstHeardAt = firstHeardAt ?? now
        lastHeardAt = now
        captionChanges += 1
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

    var heard: String {
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
