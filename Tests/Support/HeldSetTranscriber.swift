import Testing

@testable import WorkoutTracker

/// A transcriber that parks `start` and `finish` until the test releases each, and captions what
/// the test says in between.
@MainActor
final class HeldSetTranscriber: SetTranscriber {
    let starting = HeldCall()
    let finishing = HeldCall()
    private(set) var wasCancelled = false
    private let candidates: [String]
    private let recording: [Float]
    private var hearing: (@MainActor (String) -> Void)?

    /// `recording` is the audio its mic hands the recorder: none, as a Simulator's, unless the test
    /// is about the recording engine.
    init(candidates: [String], recording: [Float] = []) {
        self.candidates = candidates
        self.recording = recording
    }

    func start(hearing: @escaping @MainActor (String) -> Void, recording recorder: DictationRecorder) async throws(SetTranscriberError) {
        await starting.hold()
        recording.withUnsafeBufferPointer(recorder.append)
        self.hearing = hearing
        hearing(candidates.first ?? "")
    }

    /// Captions `words`, as the engine does while it listens and as it finalizes.
    func hear(_ words: String) {
        hearing?(words)
    }

    func finish() async throws(SetTranscriberError) -> [String] {
        await finishing.hold()
        return candidates
    }

    func cancel() async {
        wasCancelled = true
    }
}
