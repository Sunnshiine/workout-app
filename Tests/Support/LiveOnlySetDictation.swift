@testable import WorkoutTracker

extension SetDictation {
    /// A Dictation whose recording engine has no model, as the Simulator's: the Live Transcript
    /// decides every press. Its records stay in memory.
    convenience init(transcriber: any SetTranscriber, clock: any ListeningClock = ContinuousListeningClock()) {
        self.init(
            transcriber: transcriber,
            reader: CannedRecordingTranscriber(answering: .missing(.modelNotReady(.absent))),
            journal: DictationJournal(storage: .inMemory),
            clock: clock
        )
    }
}
