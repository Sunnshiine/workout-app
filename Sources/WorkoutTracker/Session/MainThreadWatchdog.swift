import Foundation
import Synchronization

/// Measures the longest the main thread went without running queued work while a press was in
/// flight, which is how long the screen could not answer a touch. It pings the main queue from a
/// utility queue every `interval` and times each ping's wait.
final class MainThreadWatchdog: Sendable {
    nonisolated static let interval: Duration = .milliseconds(50)

    /// Runs a ping on the main queue.
    typealias MainQueue = @Sendable (@escaping @Sendable () -> Void) -> Void

    private struct State {
        /// When the ping still waiting on the main queue was sent.
        var waitingSince: ContinuousClock.Instant?
        var longest: Duration = .zero

        mutating func waited(until now: ContinuousClock.Instant) {
            guard let waitingSince else { return }
            longest = max(longest, now - waitingSince)
        }
    }

    private let state = Mutex(State())
    private let clock: @Sendable () -> ContinuousClock.Instant
    private let mainQueue: MainQueue
    /// Nil when a test pings in its place.
    private let timer: (any DispatchSourceTimer)?

    /// Pings the main queue every `interval` until `stop()`.
    convenience init() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        self.init(clock: { .now }, mainQueue: { DispatchQueue.main.async(execute: $0) }, timer: timer)
        let interval = DispatchTimeInterval.milliseconds(Self.interval.wholeMilliseconds)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.ping() }
        timer.resume()
    }

    /// Pings only when a test calls `ping()`, reading the test's clock and sending to its queue.
    convenience init(clock: @escaping @Sendable () -> ContinuousClock.Instant, mainQueue: @escaping MainQueue) {
        self.init(clock: clock, mainQueue: mainQueue, timer: nil)
    }

    private init(
        clock: @escaping @Sendable () -> ContinuousClock.Instant,
        mainQueue: @escaping MainQueue,
        timer: (any DispatchSourceTimer)?
    ) {
        self.clock = clock
        self.mainQueue = mainQueue
        self.timer = timer
    }

    deinit {
        timer?.cancel()
    }

    /// The longest wait so far, counting a ping still waiting. The watchdog stops pinging.
    func stop() -> Duration {
        timer?.cancel()
        let now = clock()
        return state.withLock { state in
            state.waited(until: now)
            return state.longest
        }
    }

    /// One tick of the timer. A ping still waiting holds the next one back, so a stalled main
    /// thread has one ping queued, not one per interval.
    func ping() {
        let now = clock()
        let isWaiting = state.withLock { state in
            state.waited(until: now)
            guard state.waitingSince == nil else { return true }
            state.waitingSince = now
            return false
        }
        guard !isWaiting else { return }
        mainQueue { [weak self] in
            guard let self else { return }
            let now = clock()
            state.withLock { state in
                state.waited(until: now)
                state.waitingSince = nil
            }
        }
    }
}
