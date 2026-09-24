import Testing

/// Parks at most `parks` calls, one at a time, and returns at once from a call made while another
/// is held, after the budget is spent, or after a poll gave up. A continuation ignores the time
/// limit's cancellation, so a call parked where no release reaches it would hang the run.
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
        for _ in 0..<10_000 {
            if isHeld { return }
            await Task.yield()
        }
        parksLeft = 0
        Issue.record(failure, sourceLocation: sourceLocation)
    }

    func release() {
        let continuation = parked
        parked = nil
        continuation?.resume()
    }
}
