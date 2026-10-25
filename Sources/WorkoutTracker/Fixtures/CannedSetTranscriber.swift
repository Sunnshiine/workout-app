#if DEBUG
    /// Hears its transcripts at once, for the Simulator, where SpeechAnalyzer does not run, and
    /// records `samples` for the recording engine as the mic goes live.
    @MainActor
    final class CannedSetTranscriber: SetTranscriber {
        private let candidates: [String]
        private let samples: [Float]

        init(candidates: [String], recording samples: [Float] = []) {
            self.candidates = candidates
            self.samples = samples
        }

        func start(hearing: @escaping @MainActor (String) -> Void, recording: DictationRecorder) async throws(SetTranscriberError) {
            samples.withUnsafeBufferPointer(recording.append)
            hearing(candidates.first ?? "")
        }

        func finish() async throws(SetTranscriberError) -> [String] {
            candidates
        }

        func cancel() async {}
    }
#endif
