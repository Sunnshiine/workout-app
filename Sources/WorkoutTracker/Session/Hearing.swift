/// What the speech engines heard for one press: everything the write policy reads. Each engine's
/// transcripts stay its own, so one engine's alternatives never settle a value the other cut off.
struct Hearing: Equatable, Sendable {
    let live: LiveHearing
    /// The Recording Transcript; nil when no engine read the press's recording.
    let recording: String?
}

/// The Live Transcript, or why the engine that listened as the athlete spoke has none.
enum LiveHearing: Equatable, Sendable {
    /// The most likely first. Empty when the engine heard nothing.
    case transcripts([String])
    /// The engine failed as the press ended, having captioned `caption`.
    case failed(SetTranscriberError, caption: String)
}

/// How the two engines' outcomes for one press compare, whatever the rule. Only `logged` and
/// `skipped` write.
enum EngineAgreement: String, Equatable, Sendable, Codable {
    /// No Recording Transcript.
    case liveOnly
    /// Both write the same Set Log, or both skip.
    case agreed
    /// Both write, differently.
    case disagreed
    /// Only the Recording Transcript writes.
    case recordingAlone
    /// The Live Transcript writes where the Recording Transcript does not, or fills the card where
    /// the Recording Transcript is rejected: what `gate` shows the athlete for a tap.
    case liveFills
    /// Neither writes, and the Live Transcript has no fill where the Recording Transcript was rejected.
    case neither
}

/// How the two engines' outcomes become the press's. `shipped` decides every press. The others
/// stay so a recorded press can be decided again under each before a change of rule ships.
enum MergeRule: String, CaseIterable, Sendable, Codable, CodingKeyRepresentable {
    /// The Recording Transcript leads, and a write the Live Transcript reads differently becomes a
    /// guess the athlete confirms.
    case gate
    /// The Recording Transcript leads unchecked.
    case lead
    /// The Live Transcript alone, as before a second engine.
    case liveOnly
    /// The Recording Transcript alone: a press with none heard nothing.
    case recordingOnly

    static let shipped = MergeRule.lead

    func decide(_ hearing: Hearing, in context: SpokenSetContext) -> SetDictation.Decision {
        let live = SetDictation.outcome(of: hearing.live, in: context)
        guard let transcript = hearing.recording else {
            let unread: SetDictation.Outcome = self == .recordingOnly ? .rejected(.spokenSet(.nothingHeard), heard: "") : live
            return SetDictation.Decision(outcome: unread, agreement: .liveOnly, live: live, recording: nil)
        }
        let recording = SetDictation.outcome(of: .transcripts([transcript]), in: context)
        let agreement = EngineAgreement(recording: recording, live: live)
        return SetDictation.Decision(
            outcome: outcome(agreement, live: live, recording: recording),
            agreement: agreement,
            live: live,
            recording: recording
        )
    }

    private func outcome(
        _ agreement: EngineAgreement,
        live: SetDictation.Outcome,
        recording: SetDictation.Outcome
    ) -> SetDictation.Outcome {
        switch (self, agreement) {
        case (.liveOnly, _): live
        case (.gate, .disagreed): recording.guessed
        case (.gate, .liveFills): live.guessed
        case (.gate, _), (.lead, _), (.recordingOnly, _): recording
        }
    }
}

extension EngineAgreement {
    fileprivate init(recording: SetDictation.Outcome, live: SetDictation.Outcome) {
        switch (recording.effect, live.effect) {
        case (.writes(let recorded), .writes(let heard)): self = recorded == heard ? .agreed : .disagreed
        case (.writes, _): self = .recordingAlone
        case (_, .writes), (.rejects, .fills): self = .liveFills
        default: self = .neither
        }
    }
}

extension SetDictation {
    /// A press's outcome, and how the two engines' outcomes became it.
    struct Decision: Equatable, Sendable {
        let outcome: Outcome
        let agreement: EngineAgreement
        /// Each engine's outcome on its own.
        let live: Outcome
        let recording: Outcome?
    }

    /// The write policy, under the shipped rule.
    nonisolated static func decision(of hearing: Hearing, in context: SpokenSetContext) -> Decision {
        MergeRule.shipped.decide(hearing, in: context)
    }

    fileprivate nonisolated static func outcome(of live: LiveHearing, in context: SpokenSetContext) -> Outcome {
        switch live {
        case .transcripts(let candidates): outcome(of: candidates, in: context)
        case .failed(let error, let caption): .rejected(.transcriber(error), heard: caption)
        }
    }

    /// One engine's transcripts. They write only when the most likely one reads as a complete Set
    /// Log or a skip, read with the words its alternatives heard where it lost them and a value it
    /// cut off settled by every alternative that hears the same Set: a less likely transcript that
    /// reads on its own is a guess the athlete confirms.
    private nonisolated static func outcome(of candidates: [String], in context: SpokenSetContext) -> Outcome {
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
        let read: Outcome =
            switch resolution {
            case .log(let setLog): .logged(setLog, heard: heard)
            case .skip: .skipped(heard: heard)
            case .missingValues(let values): .filled(values, heard: heard)
            }
        return source == .top ? read : read.guessed
    }
}

extension SetDictation.Outcome {
    /// This reading as a guess the athlete confirms: a Set Log fills the card, and a skip, which the
    /// card cannot show, is ambiguous.
    fileprivate var guessed: Self {
        switch self {
        case .logged(let setLog, let heard): .filled(SetLogDraft(setLog), heard: heard)
        case .skipped(let heard): .rejected(.spokenSet(.ambiguous), heard: heard)
        case .filled, .rejected: self
        }
    }

    fileprivate var effect: Effect {
        switch self {
        case .logged(let setLog, _): .writes(.log(setLog))
        case .skipped: .writes(.skip)
        case .filled: .fills
        case .rejected: .rejects
        }
    }
}

/// What an outcome does to its Set, whatever was heard.
private enum Effect: Equatable {
    enum Write: Equatable {
        case log(SetLog)
        case skip
    }

    case writes(Write)
    case fills
    case rejects
}
