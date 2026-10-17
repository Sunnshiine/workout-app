import Testing

/// A continuation ignores the time limit's cancellation, so a call parked where no release reaches
/// it would hang the run.
@MainActor
final class HeldCall {
    private var parked: CheckedContinuation<Void, Never>?
    private var parksLeft: Int

    init(parks: Int = 1) {
        parksLeft = parks
    }

    var isHeld: Bool { parked != nil }

    func hold() async {
        guard parked == nil, parksLeft > 0 else { return }
        parksLeft -= 1
        await withCheckedContinuation { parked = $0 }
    }

    func waitUntilHeld(orRecord failure: Comment, sourceLocation: SourceLocation = #_sourceLocation) async {
        if await waitUntil({ isHeld }, orRecord: failure, sourceLocation: sourceLocation) { return }
        abandon()
    }

    func release() {
        let continuation = parked
        parked = nil
        continuation?.resume()
    }

    func abandon() {
        parksLeft = 0
        release()
    }
}

/// Waits for work on the main actor to make `done` true, and records `failure` instead of hanging
/// when it never does. The work that sets `done` must run on the main actor too, so each yield
/// gives it a turn.
@MainActor
@discardableResult
func waitUntil(
    _ done: () -> Bool,
    orRecord failure: Comment,
    sourceLocation: SourceLocation = #_sourceLocation
) async -> Bool {
    for _ in 0..<10_000 {
        if done() { return true }
        await Task.yield()
    }
    Issue.record(failure, sourceLocation: sourceLocation)
    return false
}
