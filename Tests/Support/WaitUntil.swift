import Testing

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
