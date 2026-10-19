import Foundation

/// One press of a Dictation as it happened: what each engine heard, what each rule would have
/// decided, how long the athlete waited, and what the press cost the phone. It holds no audio.
struct DictationRecord: Equatable, Sendable {
    static let schema = 1

    let id: UUID
    let pressedAt: Date
    let app: BuildIdentity
    let surface: SetDictation.Surface
    let ending: Ending
    let timeline: Timeline
    let device: DeviceFacts
    /// The longest the main thread took to answer during the press.
    let longestMainThreadStallMs: Int

    enum Ending: Equatable, Sendable {
        case decided(Decided)
        /// Stopped before it began finishing, so nothing was decided.
        case cancelled
    }

    struct Decided: Codable, Equatable, Sendable {
        let end: PressEnd
        let set: SpokenSetContext
        let live: Live
        let recording: Recording
        let decision: Decision
    }

    /// How a decided press ended: the athlete let go, or listening with no hand on the mic stopped.
    enum PressEnd: String, Codable, Sendable {
        case released, silence, cap, nothingHeard
        /// Listening with no hand on the mic never began: the live engine failed to start.
        case unstarted
    }

    struct Live: Codable, Equatable, Sendable {
        /// The Live Transcript, the most likely first. Empty when the engine failed.
        let candidates: [String]
        let failure: SetTranscriberError?
        /// How many times the card's caption changed while the athlete spoke.
        let captionChanges: Int
    }

    struct Recording: Equatable, Sendable {
        let modelAtPress: SpeechModelState
        let modelAtEnd: SpeechModelState
        let result: RecordingDecode.Result
        let audioSeconds: Double
        let truncated: Bool
        let decodeMs: DecodeTimings?
    }

    struct Decision: Codable, Equatable, Sendable {
        let rule: MergeRule
        let agreement: EngineAgreement
        let outcome: Outcome
        let live: Outcome
        let recording: Outcome?
        /// What each rule would have decided, so a change of rule can be scored on recorded presses.
        let byRule: [MergeRule: Outcome]
    }

    /// A press's outcome as it reads in the record, with the rejection named as `say` names it.
    struct Outcome: Codable, Equatable, Sendable {
        let kind: OutcomeKind
        let heard: String
        let setLog: String?
        let draft: SetLogDraft?
        let rejection: SpokenSetRejectionSnapshot?
    }

    enum OutcomeKind: String, Codable, Sendable {
        case logged, skipped, filled, rejected
    }

    /// When the press's events happened, in whole milliseconds since it began. Nil for an event the
    /// press never reached.
    struct Timeline: Codable, Equatable, Sendable {
        let live: Int?
        let firstHeard: Int?
        let lastHeard: Int?
        let ended: Int
        let liveFinished: Int?
        let recordingRead: Int?
        /// The Recording Transcript was still being read at the Decision Deadline.
        let recordingDropped: Int?
        let decided: Int?
    }

    /// The largest share of a wait past `SetDictation.latencyTarget`.
    enum WaitCause: String, Codable, Sendable, CaseIterable {
        /// The live engine was not yet listening when the press ended.
        case liveStart
        case liveFinalize
        case recordingTranscript
        case decisionDeadline
    }
}

extension DictationRecord {
    /// From the press's end to its outcome; nil for a cancelled press.
    var waitMs: Int? {
        timeline.decided.map { $0 - timeline.ended }
    }

    var isWithinTarget: Bool? {
        waitMs.map { $0 <= SetDictation.latencyTarget.wholeMilliseconds }
    }

    /// Nil for a press within the target, or cancelled. The earlier step wins a tie, as the one
    /// the press waited on first.
    var waitCause: WaitCause? {
        guard isWithinTarget == false, let decided = timeline.decided else { return nil }
        let ended = timeline.ended
        let listening = max(ended, timeline.live ?? decided)
        let finalized = timeline.liveFinished ?? decided
        let shares: [(WaitCause, Int)] = [
            (.liveStart, listening - ended),
            (.liveFinalize, finalized - listening),
            (timeline.recordingDropped == nil ? .recordingTranscript : .decisionDeadline, decided - finalized)
        ]
        return shares.max { $0.1 < $1.1 }?.0
    }
}

extension DictationRecord.PressEnd {
    init(_ reason: SetDictation.StopReason) {
        switch reason {
        case .silence: self = .silence
        case .cap: self = .cap
        case .nothingHeard: self = .nothingHeard
        }
    }
}

extension DictationRecord.Live {
    init(_ live: LiveHearing, captionChanges: Int) {
        switch live {
        case .transcripts(let candidates): self.init(candidates: candidates, failure: nil, captionChanges: captionChanges)
        case .failed(let failure, _): self.init(candidates: [], failure: failure, captionChanges: captionChanges)
        }
    }
}

extension DictationRecord.Recording {
    init(modelAtPress: SpeechModelState, modelAtEnd: SpeechModelState, decode: RecordingDecode, of recording: DictationRecording) {
        self.init(
            modelAtPress: modelAtPress,
            modelAtEnd: modelAtEnd,
            result: decode.result,
            audioSeconds: Double(recording.samples.count) / Double(DictationRecorder.sampleRate),
            truncated: recording.isTruncated,
            decodeMs: decode.timings
        )
    }
}

extension DictationRecord.Decision {
    /// `decision`, the shipped rule's, beside what every rule decides from the same hearing.
    init(_ decision: SetDictation.Decision, of hearing: Hearing, in context: SpokenSetContext) {
        self.init(
            rule: .shipped,
            agreement: decision.agreement,
            outcome: DictationRecord.Outcome(decision.outcome),
            live: DictationRecord.Outcome(decision.live),
            recording: decision.recording.map(DictationRecord.Outcome.init),
            byRule: Dictionary(
                uniqueKeysWithValues: MergeRule.allCases.map { ($0, DictationRecord.Outcome($0.decide(hearing, in: context).outcome)) }
            )
        )
    }
}

extension DictationRecord.Timeline {
    init(_ timeline: PressTimeline) {
        func since(_ instant: Duration) -> Int { (instant - timeline.pressedAt).wholeMilliseconds }
        self.init(
            live: timeline.wentLiveAt.map(since),
            firstHeard: timeline.firstHeardAt.map(since),
            lastHeard: timeline.lastHeardAt.map(since),
            ended: since(timeline.endedAt ?? timeline.pressedAt),
            liveFinished: timeline.liveFinishedAt.map(since),
            recordingRead: timeline.recordingReadAt.map(since),
            recordingDropped: timeline.recordingDroppedAt.map(since),
            decided: timeline.decidedAt.map(since)
        )
    }
}

extension DictationRecord.Outcome {
    init(_ outcome: SetDictation.Outcome) {
        switch outcome {
        case .logged(let setLog, let heard):
            self.init(kind: .logged, heard: heard, setLog: setLog.formatted, draft: nil, rejection: nil)
        case .skipped(let heard):
            self.init(kind: .skipped, heard: heard, setLog: nil, draft: nil, rejection: nil)
        case .filled(let draft, let heard):
            self.init(kind: .filled, heard: heard, setLog: nil, draft: draft, rejection: nil)
        case .rejected(let rejection, let heard):
            self.init(kind: .rejected, heard: heard, setLog: nil, draft: nil, rejection: SpokenSetRejectionSnapshot(dictation: rejection))
        }
    }
}

extension DictationRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case schema, id, pressedAt, app, surface, end, timelineMs, device, longestMainThreadStallMs
    }

    private static let cancelled = "cancelled"

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(Int.self, forKey: .schema)
        guard schema == Self.schema else {
            let description = "Schema \(schema) is not \(Self.schema)"
            throw DecodingError.dataCorruptedError(forKey: .schema, in: container, debugDescription: description)
        }
        id = try container.decode(UUID.self, forKey: .id)
        pressedAt = try container.decode(Date.self, forKey: .pressedAt)
        app = try container.decode(BuildIdentity.self, forKey: .app)
        surface = try container.decode(SetDictation.Surface.self, forKey: .surface)
        let isCancelled = try container.decode(String.self, forKey: .end) == Self.cancelled
        ending = isCancelled ? .cancelled : .decided(try Decided(from: decoder))
        timeline = try container.decode(Timeline.self, forKey: .timelineMs)
        device = try container.decode(DeviceFacts.self, forKey: .device)
        longestMainThreadStallMs = try container.decode(Int.self, forKey: .longestMainThreadStallMs)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schema, forKey: .schema)
        try container.encode(id, forKey: .id)
        try container.encode(pressedAt, forKey: .pressedAt)
        try container.encode(app, forKey: .app)
        try container.encode(surface, forKey: .surface)
        switch ending {
        case .decided(let decided): try decided.encode(to: encoder)
        case .cancelled: try container.encode(Self.cancelled, forKey: .end)
        }
        try container.encode(timeline, forKey: .timelineMs)
        try container.encode(device, forKey: .device)
        try container.encode(longestMainThreadStallMs, forKey: .longestMainThreadStallMs)
    }

    /// One record per line, keys sorted, so a journal reads the same wherever it was written.
    static func lineEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func lineDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension DictationRecord.Recording: Codable {
    private enum CodingKeys: String, CodingKey {
        case modelAtPress, modelAtEnd, transcript, segments, miss, audioSeconds, truncated, decodeMs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelAtPress = try container.decode(SpeechModelState.self, forKey: .modelAtPress)
        modelAtEnd = try container.decode(SpeechModelState.self, forKey: .modelAtEnd)
        if let miss = try container.decodeIfPresent(RecordingMiss.self, forKey: .miss) {
            result = .missing(miss)
        } else {
            result = .heard(
                try container.decode(String.self, forKey: .transcript),
                segments: try container.decode([SegmentScore].self, forKey: .segments)
            )
        }
        audioSeconds = try container.decode(Double.self, forKey: .audioSeconds)
        truncated = try container.decode(Bool.self, forKey: .truncated)
        decodeMs = try container.decodeIfPresent(DecodeTimings.self, forKey: .decodeMs)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelAtPress, forKey: .modelAtPress)
        try container.encode(modelAtEnd, forKey: .modelAtEnd)
        switch result {
        case .heard(let transcript, let segments):
            try container.encode(transcript, forKey: .transcript)
            try container.encode(segments, forKey: .segments)
        case .missing(let miss):
            try container.encode(miss, forKey: .miss)
        }
        try container.encode(audioSeconds, forKey: .audioSeconds)
        try container.encode(truncated, forKey: .truncated)
        try container.encodeIfPresent(decodeMs, forKey: .decodeMs)
    }
}

extension RecordingMiss: Codable {
    /// The miss as the record and the summary name it, as "modelNotReady.absent".
    var reason: String {
        switch self {
        case .modelNotReady(let model): "modelNotReady.\(model.rawValue)"
        case .failed: "failed"
        // The case's own name, which the reason table in the tests pins.
        case .late, .tooHot, .nothingRecorded, .notAsked: String(describing: self)
        }
    }

    private static let failedPrefix = "failed: "

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        if text.hasPrefix(Self.failedPrefix) {
            self = .failed(String(text.dropFirst(Self.failedPrefix.count)))
            return
        }
        let unmissed: [RecordingMiss] = [.late, .tooHot, .nothingRecorded, .notAsked]
        let misses = unmissed + [SpeechModelState.absent, .ready].map(RecordingMiss.modelNotReady)
        guard let miss = misses.first(where: { $0.reason == text }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\"\(text)\" is not a recording miss")
        }
        self = miss
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        guard case .failed(let message) = self else {
            try container.encode(reason)
            return
        }
        try container.encode(Self.failedPrefix + message)
    }
}

extension DecodeTimings: Codable {
    private enum CodingKeys: String, CodingKey {
        case queued, mel, encode, decodeLoop, total, tokens, fallbacks
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func milliseconds(_ key: CodingKeys) throws -> Duration { .milliseconds(try container.decode(Int.self, forKey: key)) }
        self.init(
            queued: try milliseconds(.queued),
            melSpectrogram: try milliseconds(.mel),
            encoding: try milliseconds(.encode),
            decodingLoop: try milliseconds(.decodeLoop),
            total: try milliseconds(.total),
            tokens: try container.decode(Int.self, forKey: .tokens),
            fallbacks: try container.decode(Int.self, forKey: .fallbacks)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(queued.wholeMilliseconds, forKey: .queued)
        try container.encode(melSpectrogram.wholeMilliseconds, forKey: .mel)
        try container.encode(encoding.wholeMilliseconds, forKey: .encode)
        try container.encode(decodingLoop.wholeMilliseconds, forKey: .decodeLoop)
        try container.encode(total.wholeMilliseconds, forKey: .total)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(fallbacks, forKey: .fallbacks)
    }
}

extension SetLogDraft: Codable {
    private enum CodingKeys: String, CodingKey {
        case weight, reps, rpe
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let weight = try container.decodeIfPresent(String.self, forKey: .weight)
        let rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
        self.init(
            weight: try weight.map { text in
                guard let weight = Weight(text: text) else {
                    throw DecodingError.dataCorruptedError(forKey: .weight, in: container, debugDescription: "\"\(text)\" is not a weight")
                }
                return weight
            },
            reps: try container.decodeIfPresent(Int.self, forKey: .reps),
            rpe: try rpe.map { point in
                guard let rpe = RPE(rawValue: point) else {
                    throw DecodingError.dataCorruptedError(forKey: .rpe, in: container, debugDescription: "\(point) is not an RPE")
                }
                return rpe
            }
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(weight?.label, forKey: .weight)
        try container.encodeIfPresent(reps, forKey: .reps)
        try container.encodeIfPresent(rpe?.rawValue, forKey: .rpe)
    }
}

extension SpokenSetContext: Codable {
    private enum CodingKeys: String, CodingKey {
        case block, address, exercise, draft, previous
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let address = try container.decodeIfPresent(SetAddress.self, forKey: .address)
        let set = try address.map { address in
            DictatedSet(
                block: try container.decode(String.self, forKey: .block),
                address: address,
                exercise: try container.decode(String.self, forKey: .exercise)
            )
        }
        let previous = try container.decodeIfPresent(String.self, forKey: .previous)
        self.init(
            set: set,
            draft: try container.decode(SetLogDraft.self, forKey: .draft),
            previous: try previous.map { text in
                guard let setLog = SetLog(formatted: text) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .previous,
                        in: container,
                        debugDescription: "\"\(text)\" is not a Set Log"
                    )
                }
                return setLog
            }
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(set?.block, forKey: .block)
        try container.encodeIfPresent(set?.address, forKey: .address)
        try container.encodeIfPresent(set?.exercise, forKey: .exercise)
        try container.encode(draft, forKey: .draft)
        try container.encodeIfPresent(previous?.formatted, forKey: .previous)
    }
}

extension Duration {
    /// Rounded to the nearest millisecond, as a record keeps time.
    var wholeMilliseconds: Int {
        let (seconds, attoseconds) = components
        return Int((Double(seconds) * 1000 + Double(attoseconds) / 1e15).rounded())
    }
}
