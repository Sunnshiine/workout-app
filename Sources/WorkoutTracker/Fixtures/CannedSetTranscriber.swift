#if DEBUG
    /// Hears its transcripts at once, for the Simulator, where SpeechAnalyzer does not run.
    @MainActor
    final class CannedSetTranscriber: SetTranscriber {
        private let candidates: [String]

        init(candidates: [String]) {
            self.candidates = candidates
        }

        func start(hearing: @escaping @MainActor (String) -> Void) async throws(SetTranscriberError) {
            hearing(candidates.first ?? "")
        }

        func finish() async throws(SetTranscriberError) -> [String] {
            candidates
        }

        func cancel() async {}
    }
#endif
