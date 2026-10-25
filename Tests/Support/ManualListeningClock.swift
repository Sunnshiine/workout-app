import Foundation
import Testing

@testable import WorkoutTracker

/// A `ListeningClock` whose time moves only when a test advances it, and whose sleepers wake only
/// when it passes their deadline.
@MainActor
final class ManualListeningClock: ListeningClock {
    private(set) var now: Duration = .zero
    var date: Date { Date(timeIntervalSince1970: 1_792_400_000) + TimeInterval(now.wholeMilliseconds) / 1000 }
    private var sleepers: [(deadline: Duration, wake: CheckedContinuation<Void, Never>)] = []

    func sleep(until deadline: Duration) async {
        guard deadline > now else { return }
        // advance(by:) wakes a sleeper at its deadline. A failed waitUntilSleeping wakes only the
        // sleepers parked when it fails, so a sleep that starts later still parks.
        // swiftlint:disable:next tests_never_park_on_a_bare_continuation
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

    /// A continuation ignores cancellation, so a failed wait wakes the sleepers parked at that moment
    /// rather than leave them parked. A sleep that starts after it still parks.
    func waitUntilSleeping(
        until deadline: Duration,
        orRecord failure: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        if await waitUntil({ sleepers.contains { $0.deadline == deadline } }, orRecord: failure, sourceLocation: sourceLocation) {
            return
        }
        let parked = sleepers
        sleepers = []
        for sleeper in parked {
            sleeper.wake.resume()
        }
    }
}
