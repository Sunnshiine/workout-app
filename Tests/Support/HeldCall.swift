import Testing

/// A continuation ignores cancellation, so a call parked where no release reaches it would hang the
/// run instead of failing it.
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
