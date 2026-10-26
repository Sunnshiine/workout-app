import Foundation

/// What a journal's Dictation Records add up to: how presses ended, what they decided and what each
/// rule would have, how the engines compared, how long the athlete waited against the target, what
/// the guardrail caught, and what each press cost the phone.
public struct DictationSummary: Encodable, Equatable, Sendable {
    /// Nearest-rank percentiles.
    public struct Percentiles: Encodable, Equatable, Sendable {
        let p50: Int
        let p90: Int
        let p99: Int
        let max: Int
    }

    public struct Recording: Encodable, Equatable, Sendable {
        /// Presses with a Recording Transcript.
        let read: Int
        /// Presses without one, by why.
        let missing: [String: Int]
        let decodeMs: Percentiles?
    }

    /// Release to outcome, which `SetDictation.latencyTarget` sets the target for.
    public struct Latency: Encodable, Equatable, Sendable {
        let targetMs: Int
        let withinTarget: Int
        let missedTarget: Int
        let waitMs: Percentiles?
        /// The misses, by their largest share of the wait.
        let waitCause: [String: Int]
    }

    /// Engine outcomes rejected as a Set no lifter logs, by engine and field.
    public struct Guardrail: Encodable, Equatable, Sendable {
        let implausible: [String: [String: Int]]
    }

    public struct Hazards: Encodable, Equatable, Sendable {
        /// Recording Transcripts holding a numeral of the recording engine's prompt that the Live
        /// Transcript does not.
        let promptEcho: Int
    }

    let presses: Int
    /// Lines that did not read as a record: one cut off mid-write, or of another schema.
    let unreadableLines: Int
    let surfaces: [String: Int]
    let ends: [String: Int]
    /// Presses whose mic never went live, by the step that refused it and the phone's error.
    let micStartRefusals: [String: Int]
    /// What each decided press did under the rule that shipped.
    let outcomes: [String: Int]
    /// What each decided press would have done under each rule.
    let byRule: [String: [String: Int]]
    let agreement: [String: Int]
    let recording: Recording
    let latency: Latency
    let guardrail: Guardrail
    let hazards: Hazards
    let longestMainThreadStallMs: Percentiles?
    let footprintMB: Percentiles?
    /// The outcome that decided each press, against its export's labels. Nil without labels.
    let scored: DictationScore?
    let caveats: [String]

    static let unlabelled = "No press is labelled yet, so nothing here says whether a write was right."

    static let caveats = [
        "Agreement compares the engines only where both read the press. A press with no Recording Transcript is liveOnly.",
        "promptEcho compares the Recording Transcript with the Live Transcript, not with what the athlete said."
    ]
}

extension DictationSummary {
    init(_ records: [DictationRecord], unreadableLines: Int, labels: DictationLabels?) {
        let decided = records.compactMap(\.decided)
        let timed = records.compactMap { record in record.waitMs.map { (record, $0) } }
        let fields = SetLogDraft.Field.allCases.map(\.rawValue)
        presses = records.count
        self.unreadableLines = unreadableLines
        surfaces = Self.counts(records.map(\.surface.rawValue))
        ends = Self.counts(records.map { $0.decided?.end.rawValue ?? "cancelled" })
        micStartRefusals = Self.counts(decided.compactMap { $0.live.startRefusal.map { "\($0.step) \($0.error)" } })
        outcomes = Self.counts(decided.map(\.decision.outcome.kind.rawValue))
        byRule = Dictionary(
            uniqueKeysWithValues: MergeRule.allCases.map { rule in
                (rule.rawValue, Self.counts(decided.compactMap { $0.decision.byRule[rule]?.kind.rawValue }))
            }
        )
        agreement = Self.counts(decided.map(\.decision.agreement.rawValue))
        recording = Recording(
            read: decided.count { $0.recording.result.transcript != nil },
            missing: Self.counts(
                decided.compactMap {
                    guard case .missing(let miss) = $0.recording.result else { return nil }
                    return miss.reason
                }
            ),
            decodeMs: Percentiles(decided.compactMap { $0.recording.decodeMs?.total.wholeMilliseconds })
        )
        latency = Latency(
            targetMs: SetDictation.latencyTarget.wholeMilliseconds,
            withinTarget: timed.count { $0.0.isWithinTarget == true },
            missedTarget: timed.count { $0.0.isWithinTarget == false },
            waitMs: Percentiles(timed.map(\.1)),
            waitCause: Self.counts(timed.compactMap { $0.0.waitCause?.rawValue })
        )
        guardrail = Guardrail(
            implausible: [
                "live": Self.counts(decided.compactMap { $0.decision.live.implausibleField }, of: fields),
                "recording": Self.counts(decided.compactMap { $0.decision.recording?.implausibleField }, of: fields)
            ]
        )
        hazards = Hazards(promptEcho: decided.count { $0.echoes(.p1) })
        longestMainThreadStallMs = Percentiles(records.map(\.longestMainThreadStallMs))
        footprintMB = Percentiles(records.map(\.device.footprintMB))
        scored = labels.map { labels in
            let byRecord = labels.byRecord
            return DictationScore(
                records.compactMap { record in
                    record.decided.map { ($0.decision.outcome, byRecord[record.id]?.truth) }
                }
            )
        }
        caveats = (labels == nil ? [Self.unlabelled] : DictationScore.caveats) + Self.caveats
    }

    private static func counts(_ keys: [String], of every: [String] = []) -> [String: Int] {
        keys.reduce(into: Dictionary(uniqueKeysWithValues: every.map { ($0, 0) })) { counts, key in counts[key, default: 0] += 1 }
    }
}

extension DictationSummary.Percentiles {
    /// Nil for no values.
    init?(_ values: [Int]) {
        let sorted = values.sorted()
        guard let max = sorted.last else { return nil }
        func rank(_ fraction: Double) -> Int {
            sorted[Swift.max(0, Int((fraction * Double(sorted.count)).rounded(.up)) - 1)]
        }
        self.init(p50: rank(0.5), p90: rank(0.9), p99: rank(0.99), max: max)
    }
}

extension DictationRecord {
    var decided: Decided? {
        guard case .decided(let decided) = ending else { return nil }
        return decided
    }
}

extension DictationRecord.Outcome {
    /// The field of a rejection as a Set no lifter logs.
    fileprivate var implausibleField: String? {
        guard rejection?.reason == .implausible else { return nil }
        return rejection?.field
    }
}

extension DictationRecord.Decided {
    /// Whether the Recording Transcript holds a numeral of `prompt` that no Live Transcript does. A
    /// press with no Live Transcript to compare with never counts.
    func echoes(_ prompt: RecordingPrompt) -> Bool {
        guard let transcript = recording.result.transcript, !live.candidates.isEmpty else { return false }
        let said = live.candidates.reduce(into: Set<String>()) { said, candidate in said.formUnion(Self.numerals(in: candidate)) }
        return !Self.numerals(in: transcript).intersection(Self.numerals(in: prompt.text)).subtracting(said).isEmpty
    }

    /// "1,290 for 5" holds 1290 and 5.
    private static func numerals(in text: String) -> Set<String> {
        let joined = text.replacing(/(\d),(\d{3})/) { "\($0.1)\($0.2)" }
        return Set(joined.matches(of: /\d+(\.\d+)?/).map { String($0.output.0) })
    }
}

/// The three classes `scripts/measure-dictation.sh` scores a press in against what the athlete
/// meant, the one definition every score of a press uses.
enum DictationScoring {
    enum Class: String, Encodable, Sendable {
        case correct = "CORRECT"
        case wrong = "WRONG"
        case nowrite = "NOWRITE"
    }

    /// What a press wrote to its Set.
    enum Write: Equatable, Sendable {
        /// As the Sheet holds it, as "185x5@8".
        case setLog(String)
        case skip
    }

    /// What the athlete meant the press to do.
    enum Truth: Equatable, Sendable {
        case write(Write)
        /// Nothing: what was said is not a Set.
        case reject
    }

    /// CORRECT wrote exactly what was meant, or nothing for a reject. WRONG wrote anything else.
    /// NOWRITE wrote nothing where a write was meant.
    static func classify(written: Write?, truth: Truth) -> Class {
        guard let written else { return truth == .reject ? .correct : .nowrite }
        return truth == .write(written) ? .correct : .wrong
    }
}

/// How one rule's outcomes scored against what the athlete meant, every class through
/// `DictationScoring.classify`. A press with nothing to say what was meant is unscored.
public struct DictationScore: Encodable, Equatable, Sendable {
    let correct: Int
    let wrong: Int
    let nowrite: Int
    let unscored: Int

    private enum CodingKeys: String, CodingKey {
        case correct = "CORRECT"
        case wrong = "WRONG"
        case nowrite = "NOWRITE"
        case unscored
    }

    init(_ presses: [(outcome: DictationRecord.Outcome, truth: DictationScoring.Truth?)]) {
        let classes = presses.compactMap { press in
            press.truth.map { DictationScoring.classify(written: press.outcome.written, truth: $0) }
        }
        correct = classes.count { $0 == .correct }
        wrong = classes.count { $0 == .wrong }
        nowrite = classes.count { $0 == .nowrite }
        unscored = presses.count - classes.count
    }

    static let caveats = [
        "Only a press whose outcome wrote a Set has a label, so the rule that decided a press never scores NOWRITE.",
        "Another rule's write on a press nothing wrote is unscored.",
        "A correction is a lower bound on wrong writes. An athlete who never notices a wrong write never corrects it.",
        "A Set the athlete cleared and left Pending is unscored."
    ]
}

extension DictationRecord.Outcome {
    /// What the outcome wrote: only `logged` and `skipped` write.
    var written: DictationScoring.Write? {
        switch kind {
        case .logged: setLog.map(DictationScoring.Write.setLog)
        case .skipped: .skip
        case .filled, .rejected: nil
        }
    }
}
