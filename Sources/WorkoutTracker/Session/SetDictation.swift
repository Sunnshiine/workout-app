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

/// Speech-to-text for one Spoken Set: listens from `start` until `finish`.
@MainActor
protocol SetTranscriber: AnyObject {
    /// Returns once the microphone is live. `hearing` receives the whole transcript so far each
    /// time it changes, until `finish` or `cancel` returns. A start that throws leaves nothing
    /// listening.
    func start(hearing: @escaping @MainActor (String) -> Void) async throws(SetTranscriberError)
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

    private(set) var state: State = .idle
    @ObservationIgnored private let transcriber: any SetTranscriber
    @ObservationIgnored private let clock: any ListeningClock
    /// Held from `start` until `finish` or `cancel` takes it: nil means no press is in flight.
    @ObservationIgnored private var starting: Task<SetTranscriberError?, Never>?
    @ObservationIgnored private var wentLiveAt: Duration?
    @ObservationIgnored private var lastHeardAt: Duration?

    init(transcriber: any SetTranscriber, clock: any ListeningClock = ContinuousListeningClock()) {
        self.transcriber = transcriber
        self.clock = clock
    }

    /// Ignored, returning false, while another press is in flight, so one transcriber never
    /// listens twice.
    @discardableResult
    func start(for set: ActiveSetID) -> Bool {
        guard starting == nil, state.listeningSetID == nil else { return false }
        state = .preparing(set)
        wentLiveAt = nil
        lastHeardAt = nil
        let transcriber = transcriber
        starting = Task { [weak self] in
            do throws(SetTranscriberError) {
                try await transcriber.start { [weak self] heard in self?.hear(heard, for: set) }
                self?.hear(nil, for: set)
                return nil
            } catch {
                return error
            }
        }
        return true
    }

    /// Listens for `set` with no hand on the mic until the athlete stops talking, then finishes as
    /// a release would. Nothing heard by the cap writes nothing. A tap that finishes the press
    /// first, or a cancel, leaves this nil, as does a press already in flight.
    func listenUntilQuiet(for set: ActiveSetID, in context: () -> SpokenSetContext) async -> Outcome? {
        guard start(for: set), let press = starting else { return nil }
        guard await press.value == nil else { return await finish(for: set, in: context()) }
        return await listen(through: press, for: set, in: context)
    }

    private func listen(
        through press: Task<SetTranscriberError?, Never>,
        for set: ActiveSetID,
        in context: () -> SpokenSetContext
    ) async -> Outcome? {
        while starting == press, let wentLiveAt {
            switch Self.autoStop(at: clock.now, liveAt: wentLiveAt, lastHeardAt: lastHeardAt) {
            case .wake(let deadline): await clock.sleep(until: deadline)
            case .stop(.nothingHeard): return await giveUpHearingNothing(for: set)
            case .stop(.silence), .stop(.cap): return await finish(for: set, in: context())
            }
        }
        return nil
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
        starting = nil
        await transcriber.cancel()
        let outcome = Outcome.rejected(.transcriber(.nothingHeard), heard: "")
        state = .finished(set, outcome)
        return outcome
    }

    /// Waits for the transcriber to start if it has not, so a release during `preparing` still
    /// finishes. Nil when no press for `set` is in flight.
    func finish(for set: ActiveSetID, in context: SpokenSetContext) async -> Outcome? {
        guard let starting, state.listeningSetID == set else { return nil }
        self.starting = nil
        let outcome: Outcome
        if let error = await starting.value {
            outcome = .rejected(.transcriber(error), heard: "")
        } else {
            do throws(SetTranscriberError) {
                outcome = Self.outcome(of: try await transcriber.finish(), in: context)
            } catch {
                outcome = .rejected(.transcriber(error), heard: state.heard)
            }
        }
        state = .finished(set, outcome)
        return outcome
    }

    /// Stops a press that has not begun finishing, writing nothing. The press stays in flight
    /// until the transcriber stops, so the next one cannot start under it.
    func cancel() async {
        guard let starting else { return }
        self.starting = nil
        _ = await starting.value
        await transcriber.cancel()
        state = .idle
    }

    func dismiss() {
        guard case .finished = state else { return }
        state = .idle
    }

    /// `heard` nil is the transcriber going live.
    private func hear(_ heard: String?, for set: ActiveSetID) {
        guard state.listeningSetID == set else { return }
        guard let heard else {
            wentLiveAt = clock.now
            state = .listening(set, heard: state.heard)
            return
        }
        if !heard.isEmpty, heard != state.heard { lastHeardAt = clock.now }
        state = .listening(set, heard: heard)
    }

    /// The write policy. A transcript writes only when the most likely one reads as a complete
    /// Set Log or a skip: a less likely transcript that reads is a guess the athlete confirms.
    nonisolated static func outcome(of candidates: [String], in context: SpokenSetContext) -> Outcome {
        let heard = candidates.first ?? ""
        let resolved = SpokenSet.parse(candidates: candidates).flatMap { chosen in
            chosen.spokenSet.resolved(against: context.draft, previous: context.previous).map { (chosen.source, $0) }
        }
        switch resolved {
        case .success((let source, let resolution)): return outcome(of: resolution, from: source, heard: heard)
        case .failure(let rejection): return .rejected(.spokenSet(rejection), heard: heard)
        }
    }

    private nonisolated static func outcome(of resolution: SpokenSetOutcome, from source: SpokenSet.Source, heard: String) -> Outcome {
        let writes = source == .top
        switch resolution {
        case .log(let setLog): return writes ? .logged(setLog, heard: heard) : .filled(SetLogDraft(setLog), heard: heard)
        case .skip: return writes ? .skipped(heard: heard) : .rejected(.spokenSet(.ambiguous), heard: heard)
        case .missingValues(let values): return .filled(values, heard: heard)
        }
    }
}

extension SetDictation.State {
    /// The Set a press in flight is for.
    var listeningSetID: ActiveSetID? {
        switch self {
        case .preparing(let set), .listening(let set, _): set
        case .idle, .finished: nil
        }
    }

    fileprivate var heard: String {
        guard case .listening(_, let heard) = self else { return "" }
        return heard
    }
}

/// What the Set card's mic and action capsule show of a press for the card's Set.
enum SetCardDictation: Equatable {
    case ready
    /// The capsule shows what is heard in place of the Log button.
    case listening(caption: String)
    /// The capsule shows what was heard, or why nothing was, until the athlete taps it.
    case rejected(caption: String)
    /// The card's values become these, with nothing written.
    case filled(SetLogDraft)

    init(_ state: SetDictation.State, for setID: ActiveSetID) {
        switch state {
        case .preparing(setID), .listening(setID, _): self = .listening(caption: state.heard.isEmpty ? "Listening" : state.heard)
        case .finished(setID, .rejected(let rejection, let heard)): self = .rejected(caption: Self.caption(rejection, heard: heard))
        case .finished(setID, .filled(let values, _)): self = .filled(values)
        case .idle, .preparing, .listening, .finished: self = .ready
        }
    }

    /// What the capsule says in place of the Log button; nil leaves the Log button.
    var caption: String? {
        switch self {
        case .listening(let caption), .rejected(let caption): caption
        case .ready, .filled: nil
        }
    }

    var isListening: Bool {
        guard case .listening = self else { return false }
        return true
    }

    private static func caption(_ rejection: SetDictation.Rejection, heard: String) -> String {
        switch rejection {
        case .transcriber(.microphoneDenied): "Microphone is off in Settings"
        case .transcriber(.unavailable): "Speech isn’t available"
        case .spokenSet(.nothingHeard), .transcriber(.nothingHeard): "Nothing heard"
        case .spokenSet, .transcriber(.failed): heard.isEmpty ? "Nothing heard" : "“\(heard)”"
        }
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
