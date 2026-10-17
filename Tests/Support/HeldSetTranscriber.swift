import Testing

@testable import WorkoutTracker

/// A transcriber that parks `start` and `finish` until the test releases each.
@MainActor
final class HeldSetTranscriber: SetTranscriber {
    let starting = HeldCall()
    let finishing = HeldCall()
    private(set) var wasCancelled = false
    private let candidates: [String]

    init(candidates: [String]) {
        self.candidates = candidates
    }

    func start(hearing: @escaping @MainActor (String) -> Void) async throws(SetTranscriberError) {
        await starting.hold()
        hearing(candidates.first ?? "")
    }

    func finish() async throws(SetTranscriberError) -> [String] {
        await finishing.hold()
        return candidates
    }

    func cancel() async {
        wasCancelled = true
    }
}
