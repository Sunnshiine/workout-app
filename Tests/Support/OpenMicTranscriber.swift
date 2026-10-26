@testable import WorkoutTracker

/// A transcriber that hears whatever the test says, when the test says it, and hands the recorder
/// whatever audio the test plays.
@MainActor
final class OpenMicTranscriber: SetTranscriber {
    let starting: HeldCall
    private(set) var finishes = 0
    private(set) var wasCancelled = false
    private let startFailure: SetTranscriberError?
    private var hearing: (@MainActor (String) -> Void)?
    private var recorder: DictationRecorder?
    private var heard = ""

    init(holdingStart: Bool, failingToStart failure: SetTranscriberError?) {
        starting = HeldCall(parks: holdingStart ? 1 : 0)
        startFailure = failure
    }

    func start(
        hearing: @escaping @MainActor (String) -> Void,
        recording recorder: DictationRecorder
    ) async throws(SetTranscriberStartError) {
        await starting.hold()
        if let startFailure { throw SetTranscriberStartError(startFailure) }
        self.hearing = hearing
        self.recorder = recorder
    }

    func say(_ words: String) {
        heard = words
        hearing?(words)
    }

    /// `samples` of 16 kHz audio, as the mic's tap hands them over.
    func play(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { recorder?.append($0) }
    }

    func finish() async throws(SetTranscriberError) -> [String] {
        finishes += 1
        hearing = nil
        return heard.isEmpty ? [] : [heard]
    }

    func cancel() async {
        wasCancelled = true
        hearing = nil
    }
}
