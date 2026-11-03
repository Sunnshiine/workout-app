@testable import WorkoutTracker

extension SetDictation {
    /// A Dictation whose recording engine reads every press as `transcript`, the Recording
    /// Transcript that decides it. Its records stay in memory.
    ///
    /// The read answers at once, but on the wall clock a loaded test run can hold its answer on the
    /// main actor past the shipped Decision Deadline, so this Dictation waits a minute for it.
    convenience init(transcriber: any SetTranscriber, reading transcript: String, clock: any ListeningClock = ContinuousListeningClock()) {
        self.init(
            transcriber: transcriber,
            reader: CannedRecordingTranscriber(answering: .heard(transcript, segments: [])),
            journal: DictationJournal(storage: .inMemory),
            clock: clock,
            decisionDeadline: .seconds(60)
        )
    }
}
