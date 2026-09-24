import Testing

/// Parks one call until the test releases it. Once `waitUntilHeld` gives up, a call that arrives
/// later returns at once: a continuation ignores the time limit's cancellation, so a call parked
/// after the poll gave up would hang the run.
@MainActor
final class HeldCall {
    private enum State {
        case idle
        case held(CheckedContinuation<Void, Never>)
        case abandoned
    }

    private var state = State.idle

    var isHeld: Bool {
        if case .held = state { return true }
        return false
    }

    func hold() async {
        if case .abandoned = state { return }
        await withCheckedContinuation { state = .held($0) }
    }

    func waitUntilHeld(orRecord failure: Comment, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<10_000 {
            if isHeld { return }
            await Task.yield()
        }
        if case .idle = state { state = .abandoned }
        Issue.record(failure, sourceLocation: sourceLocation)
    }

    func release() {
        guard case .held(let continuation) = state else { return }
        state = .idle
        continuation.resume()
    }
}
