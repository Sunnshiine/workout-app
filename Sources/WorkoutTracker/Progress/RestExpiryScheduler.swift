import Foundation

/// Drives the single "rest ended" instant for `RestTimer`. Given a deadline, it arranges for
/// the timer's `expire` closure to run once when that deadline is reached — so a rest ends on
/// its own schedule, whether or not the pill (or any view) is on screen. `RestTimer` owns the
/// expiry decision; this abstraction only owns *when* the alarm rings, which lets tests fire it
/// deterministically instead of waiting on wall-clock time.
@MainActor
protocol RestExpiryScheduling: AnyObject {
    /// Arrange for `expire` to run once at `deadline`, replacing any previously scheduled expiry.
    func schedule(deadline: Date, expire: @escaping @MainActor () -> Void)
    func cancel()
}

/// Production expiry scheduler: sleeps a lone `Task` until the deadline, then fires once. A new
/// schedule or a `cancel()` tears down any in-flight task so a restarted or dismissed rest never
/// expires against a stale deadline.
@MainActor
final class RestExpiryTimerScheduler: RestExpiryScheduling {
    private var task: Task<Void, Never>?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func schedule(deadline: Date, expire: @escaping @MainActor () -> Void) {
        cancel()
        let delay = max(0, deadline.timeIntervalSince(now()))
        task = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            expire()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
