#if DEBUG
    /// A recording engine with one answer for every press, for a fixture launch and the tests.
    final class CannedRecordingTranscriber: RecordingTranscriber {
        private let answer: RecordingDecode.Result

        init(answering answer: RecordingDecode.Result) {
            self.answer = answer
        }

        var readiness: SpeechModelState {
            guard case .heard = answer else { return .absent }
            return .ready
        }

        func expectRecording() {}

        @concurrent func transcribe(_ recording: DictationRecording) async -> RecordingDecode {
            RecordingDecode(result: answer, timings: nil)
        }
    }
#endif
