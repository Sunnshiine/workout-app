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

    private(set) var state: State = .idle
    @ObservationIgnored private let transcriber: any SetTranscriber
    /// Held from `start` until `finish` or `cancel` takes it: nil means no press is in flight.
    @ObservationIgnored private var starting: Task<SetTranscriberError?, Never>?

    init(transcriber: any SetTranscriber) {
        self.transcriber = transcriber
    }

    /// Ignored while another press is in flight, so one transcriber never listens twice.
    func start(for set: ActiveSetID) {
        guard starting == nil, state.listeningSetID == nil else { return }
        state = .preparing(set)
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

    /// `heard` nil is the transcriber going live before it has heard a word.
    private func hear(_ heard: String?, for set: ActiveSetID) {
        guard state.listeningSetID == set else { return }
        state = .listening(set, heard: heard ?? state.heard)
    }

    /// The write policy. A transcript writes only when the most likely one reads as a complete
    /// Set Log or a skip: a less likely transcript that reads is a guess the athlete confirms.
    nonisolated static func outcome(of candidates: [String], in context: SpokenSetContext) -> Outcome {
        let heard = candidates.first ?? ""
        let resolved = SpokenSet.parse(candidates: candidates).flatMap { chosen in
            chosen.spokenSet.resolved(against: context.draft, previous: context.previous).map { (chosen.source, $0) }
        }
        switch resolved {
        case .success((.top, .log(let setLog))): return .logged(setLog, heard: heard)
        case .success((.alternative, .log(let setLog))): return .filled(SetLogDraft(setLog), heard: heard)
        case .success((.top, .skip)): return .skipped(heard: heard)
        case .success((.alternative, .skip)): return .rejected(.spokenSet(.ambiguous), heard: heard)
        case .success((_, .missingValues(let values))): return .filled(values, heard: heard)
        case .failure(let rejection): return .rejected(.spokenSet(rejection), heard: heard)
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
        case .preparing(setID): self = .listening(caption: "Listening")
        case .listening(setID, let heard): self = .listening(caption: heard.isEmpty ? "Listening" : heard)
        case .finished(setID, .rejected(let rejection, let heard)): self = .rejected(caption: Self.caption(rejection, heard: heard))
        case .finished(setID, .filled(let values, _)): self = .filled(values)
        case .idle, .preparing, .listening, .finished: self = .ready
        }
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
