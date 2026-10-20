/// Speech-to-text over a press's whole recording once the athlete stops: the Recording Transcript.
/// Not main-actor isolated: a conformer runs off the main actor, and a model that is not ready
/// answers at once rather than load on the press's path.
protocol RecordingTranscriber: Sendable {
    /// Where the engine's model stands right now, without waiting.
    var readiness: SpeechModelState { get }
    /// A press began. A model that is not loaded starts loading, so this press may still get it.
    /// Never blocks and never awaits.
    func expectRecording()
    /// Reads `recording`, never on the caller's actor. On cancellation it stops within one decoder
    /// step; its answer is then ignored.
    @concurrent func transcribe(_ recording: DictationRecording) async -> RecordingDecode
}

/// The made-up earlier sentences the recording engine reads a press after, which steer it toward
/// writing numerals. Their numerals appear in no real phrasing, so one in a Recording Transcript
/// was more likely read back from the prompt than said.
struct RecordingPrompt: Equatable, Sendable {
    enum ID: String, Codable, Sendable {
        case p1
    }

    let id: ID
    let text: String

    static let p1 = RecordingPrompt(
        id: .p1,
        text: "317.5 for 3 at 6.5. 62 pounds for 11 at 9. 1290 pounds, 14 reps, RPE 7.5. For 13 at 10. Skip."
    )
}

/// What the recording engine did with one press.
struct RecordingDecode: Equatable, Sendable {
    enum Result: Equatable, Sendable {
        case heard(String, segments: [SegmentScore])
        case missing(RecordingMiss)

        /// The Recording Transcript. A reading with no words in it is nothing heard, which no
        /// transcript should lead a press with.
        var transcript: String? {
            guard case .heard(let text, _) = self, !text.allSatisfy(\.isWhitespace) else { return nil }
            return text
        }
    }

    let result: Result
    /// Nil when nothing was decoded.
    let timings: DecodeTimings?

    /// Nothing read, and why.
    static func missing(_ miss: RecordingMiss) -> RecordingDecode {
        RecordingDecode(result: .missing(miss), timings: nil)
    }

    var transcript: String? { result.transcript }
}

/// Why the recording engine read nothing for a press.
enum RecordingMiss: Equatable, Sendable {
    case modelNotReady(SpeechModelState)
    /// Still decoding at the Decision Deadline, and cancelled.
    case late
    case failed(String)
    /// Skipped to cool the phone, its thermal state critical.
    case tooHot
    case nothingRecorded
    /// The live engine heard nothing by the listening cap, so no decode was asked for.
    case notAsked
}

/// Whisper's own confidence for one segment, the inputs of a future confidence cutoff.
struct SegmentScore: Equatable, Sendable, Codable {
    let avgLogprob: Float
    let compressionRatio: Float
    let noSpeechProb: Float
    let temperature: Float
}

struct DecodeTimings: Equatable, Sendable {
    /// Waiting behind a previous, cancelled decode still unwinding.
    let queued: Duration
    let melSpectrogram: Duration
    let encoding: Duration
    let decodingLoop: Duration
    let total: Duration
    let tokens: Int
    let fallbacks: Int
}
