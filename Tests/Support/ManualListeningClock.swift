import Testing

@testable import WorkoutTracker

/// A `ListeningClock` whose time moves only when a test advances it, and whose sleepers wake only
/// when it passes their deadline.
@MainActor
final class ManualListeningClock: ListeningClock {
    private(set) var now: Duration = .zero
    private var sleepers: [(deadline: Duration, wake: CheckedContinuation<Void, Never>)] = []

    func sleep(until deadline: Duration) async {
        guard deadline > now else { return }
        await withCheckedContinuation { sleepers.append((deadline, $0)) }
    }

    func advance(by duration: Duration) {
        now += duration
        let due = sleepers.filter { $0.deadline <= now }
        sleepers.removeAll { $0.deadline <= now }
        for sleeper in due {
            sleeper.wake.resume()
        }
    }

    /// A continuation ignores the time limit's cancellation, so a failed wait wakes every sleeper
    /// rather than leave one parked.
    func waitUntilSleeping(
        until deadline: Duration,
        orRecord failure: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<10_000 {
            if sleepers.contains(where: { $0.deadline == deadline }) { return }
            await Task.yield()
        }
        let parked = sleepers
        sleepers = []
        for sleeper in parked {
            sleeper.wake.resume()
        }
        Issue.record(failure, sourceLocation: sourceLocation)
    }
}
