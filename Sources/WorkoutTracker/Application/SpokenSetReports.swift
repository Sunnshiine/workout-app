import Foundation

/// What `say` heard and what it did to the Set. `set`, `pendingWriteCount`, and
/// `exerciseIsComplete` are the report `log` returns, read after any write.
public struct SayReport: Encodable, Equatable, Sendable {
    public enum Outcome: String, Encodable, Sendable {
        case logged, skipped, missingValues, rejected
    }

    public let heard: String
    public let outcome: Outcome
    /// `logged` only.
    public let setLog: String?
    /// `missingValues` only: `weight`, `reps`, or `rpe`, in that order.
    public let missing: [String]?
    /// `rejected` only.
    public let rejection: SpokenSetRejectionSnapshot?
    public let set: SetSnapshot
    public let pendingWriteCount: Int
    public let exerciseIsComplete: Bool
}

/// `say`'s report for the most likely of `candidates`, with every transcript the recording was
/// heard as beside it.
public struct HearReport: Encodable, Equatable, Sendable {
    /// What the card would caption, and how long after the recording began to play it arrived.
    public struct Caption: Encodable, Equatable, Sendable {
        public let atMs: Int
        public let heard: String
    }

    /// The most likely first; empty when nothing was said.
    public let candidates: [String]
    /// Only for a recording played at the pace it was spoken.
    public let captions: [Caption]?
    public let report: SayReport

    init(candidates: [String], captions: [Caption]? = nil, report: SayReport) {
        self.candidates = candidates
        self.captions = captions
        self.report = report
    }

    private enum CodingKeys: String, CodingKey {
        case candidates, captions
    }

    public func encode(to encoder: any Encoder) throws {
        try report.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(candidates, forKey: .candidates)
        try container.encodeIfPresent(captions, forKey: .captions)
    }
}

extension SayReport {
    init(_ outcome: SetDictation.Outcome, report: LogReport) {
        (set, pendingWriteCount, exerciseIsComplete) = (report.set, report.pendingWriteCount, report.exerciseIsComplete)
        switch outcome {
        case .logged(let setLog, let heard):
            (self.heard, self.outcome, self.setLog, missing, rejection) = (heard, .logged, setLog.formatted, nil, nil)
        case .skipped(let heard):
            (self.heard, self.outcome, setLog, missing, rejection) = (heard, .skipped, nil, nil, nil)
        case .filled(let values, let heard):
            (self.heard, setLog) = (heard, nil)
            let unwritten = Unwritten(values)
            (self.outcome, missing, rejection) = (unwritten.outcome, unwritten.missing, unwritten.rejection)
        case .rejected(let reason, let heard):
            (self.heard, self.outcome, setLog, missing) = (heard, .rejected, nil, nil)
            rejection = SpokenSetRejectionSnapshot(dictation: reason)
        }
    }

    /// A complete Set Log read only from a less likely transcript is a guess the card would show
    /// for a tap; with no card to show it, it is `ambiguous`, as a skip read that way already is.
    private struct Unwritten {
        let outcome: Outcome
        let missing: [String]?
        let rejection: SpokenSetRejectionSnapshot?

        init(_ values: SetLogDraft) {
            let missing = SetLogDraft.Field.allCases.filter(values.missingFields.contains).map(\.rawValue)
            if missing.isEmpty {
                (outcome, self.missing, rejection) = (.rejected, nil, SpokenSetRejectionSnapshot(.ambiguous))
            } else {
                (outcome, self.missing, rejection) = (.missingValues, missing, nil)
            }
        }
    }
}

public struct SpokenSetRejectionSnapshot: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case nothingHeard, unrecognized, kilograms, fusedNumber, ambiguous, conflicting, outOfRange, implausible
        case offLadderRPE, nothingToRepeat
        /// The recognizer, not the words: the mic is off in Settings, speech is not available, or
        /// listening failed.
        case microphoneDenied, speechUnavailable, listeningFailed
        /// No Recording Transcript: the Speech Model is not ready, its read outlasted the Decision
        /// Deadline, the phone was too hot to read, or the read failed.
        case speechModelNotReady, recordingLate, tooHot, recordingFailed
    }

    public let reason: Reason
    /// `conflicting`, `outOfRange`, and `implausible` only: `weight`, `reps`, or `rpe`.
    public let field: String?
    /// `offLadderRPE` only: the number heard.
    public let value: Double?
}

extension SpokenSetRejectionSnapshot.Reason {
    fileprivate init(_ error: SetTranscriberError) {
        switch error {
        case .nothingHeard: self = .nothingHeard
        case .microphoneDenied: self = .microphoneDenied
        case .unavailable: self = .speechUnavailable
        case .failed: self = .listeningFailed
        }
    }

    fileprivate init(_ miss: RecordingMiss) {
        switch miss {
        case .notAsked, .nothingRecorded: self = .nothingHeard
        case .modelNotReady: self = .speechModelNotReady
        case .late: self = .recordingLate
        case .tooHot: self = .tooHot
        case .failed: self = .recordingFailed
        }
    }
}

extension SpokenSetRejectionSnapshot {
    init(dictation rejection: SetDictation.Rejection) {
        switch rejection {
        case .spokenSet(let reason): self.init(reason)
        case .transcriber(let error): self.init(reason: Reason(error), field: nil, value: nil)
        case .recording(let miss): self.init(reason: Reason(miss), field: nil, value: nil)
        }
    }

    init(_ rejection: SpokenSet.Rejection) {
        switch rejection {
        case .nothingHeard: self.init(reason: .nothingHeard, field: nil, value: nil)
        case .unrecognized: self.init(reason: .unrecognized, field: nil, value: nil)
        case .kilograms: self.init(reason: .kilograms, field: nil, value: nil)
        case .fusedNumber: self.init(reason: .fusedNumber, field: nil, value: nil)
        case .ambiguous: self.init(reason: .ambiguous, field: nil, value: nil)
        case .conflicting(let field): self.init(reason: .conflicting, field: field.rawValue, value: nil)
        case .outOfRange(let field): self.init(reason: .outOfRange, field: field.rawValue, value: nil)
        case .implausible(let field): self.init(reason: .implausible, field: field.rawValue, value: nil)
        case .offLadderRPE(let value): self.init(reason: .offLadderRPE, field: nil, value: value)
        case .nothingToRepeat: self.init(reason: .nothingToRepeat, field: nil, value: nil)
        }
    }
}
