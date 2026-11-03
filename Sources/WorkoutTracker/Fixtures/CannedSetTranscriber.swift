#if DEBUG
    /// Hears its transcripts at once, for the Simulator, where SpeechAnalyzer does not run, and
    /// records `samples` for the recording engine as the mic goes live.
    @MainActor
    final class CannedSetTranscriber: SetTranscriber {
        /// A second of a quiet room, which the recording engine is asked to read as a real mic's
        /// recording is, and the mic level hears as no one speaking.
        static let aSecondOfSilence = [Float](repeating: 0, count: DictationRecorder.sampleRate)

        private let candidates: [String]
        private let samples: [Float]

        init(candidates: [String], recording samples: [Float] = aSecondOfSilence) {
            self.candidates = candidates
            self.samples = samples
        }

        func start(hearing: @escaping @MainActor (String) -> Void, recording: DictationRecorder) async throws(SetTranscriberStartError) {
            samples.withUnsafeBufferPointer(recording.append)
            hearing(candidates.first ?? "")
        }

        func finish() async throws(SetTranscriberError) -> [String] {
            candidates
        }

        func cancel() async {}
    }
#endif
