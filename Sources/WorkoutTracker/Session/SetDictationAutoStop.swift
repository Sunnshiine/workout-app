/// When listening with no hand on the mic stops on its own (ADR-0021).
extension SetDictation {
    /// Why listening with no hand on the mic ended on its own.
    enum StopReason: Equatable, Sendable {
        /// The athlete paused after saying a whole Set, which a read of the recording so far heard.
        case wholeSet
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
        /// Have the recording engine read the recording so far.
        case read
        case stop(StopReason)
    }

    /// How long after the caption last changed hands-free listening ends, and about how long a
    /// Pause ends it whatever the recording engine read.
    nonisolated static let silenceWindow: Duration = .milliseconds(1200)
    /// `silenceWindow` in whole frames: 1194 ms.
    nonisolated static let pauseToStop = 14
    /// A Pause this long, 341 ms, has the recording engine read the recording so far, and stops
    /// listening when it heard a whole Set.
    nonisolated static let pauseToRead = 4
    /// How long a Pause after a whole Set whose RPE is a whole number under 10 waits for "and a
    /// half": 1024 ms. Shorter waits wrote 225x3@8 for "225 for 3 at 8 … and a half".
    nonisolated static let pauseForAHalf = 12
    /// The longest hands-free listening runs, counted from when the mic went live.
    nonisolated static let listeningCap: Duration = .seconds(8)

    /// Hands-free listening stops at the first of:
    /// - `pauseToRead` of Pause after a read of all the athlete said heard a whole Set, or
    ///   `pauseForAHalf` when its RPE is a whole number under 10;
    /// - `pauseToStop` of Pause, whatever was read;
    /// - `silenceWindow` after the caption last changed;
    /// - `listeningCap` after the mic went live, hearing nothing when neither the mic level nor
    ///   the caption heard the athlete.
    ///
    /// Short of those, `pauseToRead` of Pause with no read of all of it asks for one, and it looks
    /// again a frame on.
    nonisolated static func autoStop(
        at now: Duration,
        liveAt: Duration,
        lastHeardAt: Duration?,
        voice: VoiceActivity,
        earlyRead: HandsFreeEarlyRead?
    ) -> AutoStop {
        let readAll = earlyRead.flatMap { voice.isPaused(since: $0.samples) ? $0 : nil }
        let heardTheAthlete = voice.hasSpoken || lastHeardAt != nil
        let stopReason =
            stop(after: voice.pause, readAll: readAll)
            ?? stop(at: now, liveAt: liveAt, lastHeardAt: lastHeardAt, heardTheAthlete: heardTheAthlete)
        if let stopReason { return .stop(stopReason) }
        if asksForARead(after: voice.pause, readAll: readAll) { return .read }
        return .wake(at: wake(after: now, liveAt: liveAt, lastHeardAt: lastHeardAt))
    }

    /// A frame on, or sooner when the caption's silence window or the cap ends first.
    private nonisolated static func wake(after now: Duration, liveAt: Duration, lastHeardAt: Duration?) -> Duration {
        let cap = liveAt + listeningCap
        return min(now + VoiceActivity.frameDuration, captionQuiet(after: lastHeardAt) ?? cap, cap)
    }

    /// Why `pause` stops listening, given a read of all the athlete said before it.
    private nonisolated static func stop(after pause: VoiceActivity.Pause?, readAll: HandsFreeEarlyRead?) -> StopReason? {
        guard let pause else { return nil }
        if let stopsAfter = readAll?.heard?.stopsAfter, pause.frames >= stopsAfter { return .wholeSet }
        return pause.frames >= pauseToStop ? .silence : nil
    }

    /// Why the clock stops listening: the caption's silence window, or the cap.
    private nonisolated static func stop(at now: Duration, liveAt: Duration, lastHeardAt: Duration?, heardTheAthlete: Bool) -> StopReason? {
        let cap = liveAt + listeningCap
        if let captionQuiet = captionQuiet(after: lastHeardAt), captionQuiet <= cap, now >= captionQuiet { return .silence }
        guard now >= cap else { return nil }
        return heardTheAthlete ? .cap : .nothingHeard
    }

    private nonisolated static func captionQuiet(after lastHeardAt: Duration?) -> Duration? {
        lastHeardAt.map { $0 + silenceWindow }
    }

    private nonisolated static func asksForARead(after pause: VoiceActivity.Pause?, readAll: HandsFreeEarlyRead?) -> Bool {
        guard let pause, readAll == nil else { return false }
        return pause.frames >= pauseToRead
    }

    /// What `decode` says of the Set by itself, under the single-engine policy in `context`.
    nonisolated static func heard(_ decode: RecordingDecode, in context: SpokenSetContext) -> HandsFreeEarlyRead.Heard {
        guard let transcript = decode.transcript, case .success(let spokenSet) = SpokenSet.parse(transcript),
            writes(transcript, in: context)
        else { return .partOfASet }
        return HandsFreeEarlyRead.Heard(spokenSet)
    }

    /// Whether the recording-only single-engine policy writes the Set `transcript` says.
    private nonisolated static func writes(_ transcript: String, in context: SpokenSetContext) -> Bool {
        switch MergeRule.recordingOnly.decide(Hearing(live: .transcripts([]), recording: transcript), in: context).outcome {
        case .logged, .skipped: true
        case .filled, .rejected: false
        }
    }
}

/// A read of the recording so far, asked at a Pause, as hands-free listening sees it.
struct HandsFreeEarlyRead: Equatable, Sendable {
    /// What a Recording Transcript says of the Set by itself.
    enum Heard: Equatable, Sendable {
        /// Every value of a Set, a skip, or "same again".
        case wholeSet
        /// Every value of a Set, with an RPE that "and a half" may still follow.
        case wholeSetWithAWholeRPE
        /// Too little to stop on, or nothing.
        case partOfASet
    }

    /// How many samples of the recording it read.
    let samples: Int
    /// Nil while it is being read.
    let heard: Heard?
}

extension HandsFreeEarlyRead.Heard {
    fileprivate init(_ spokenSet: SpokenSet) {
        switch spokenSet {
        case .skip, .sameAgain: self = .wholeSet
        case .values(.heard, .heard, .heard(let rpe)): self = rpe.mayHaveAHalfToCome ? .wholeSetWithAWholeRPE : .wholeSet
        case .values: self = .partOfASet
        }
    }

    /// The Pause, in frames, that stops listening on a read that heard this.
    fileprivate var stopsAfter: Int? {
        switch self {
        case .wholeSet: SetDictation.pauseToRead
        case .wholeSetWithAWholeRPE: SetDictation.pauseForAHalf
        case .partOfASet: nil
        }
    }
}

extension RPE {
    /// A whole number under 10, which "and a half" may still follow.
    fileprivate var mayHaveAHalfToCome: Bool {
        self != .ten && rawValue.rounded() == rawValue
    }
}
