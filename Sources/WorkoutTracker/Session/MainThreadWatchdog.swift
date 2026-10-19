import Foundation
import Synchronization

/// Measures the longest the main thread went without running queued work while a press was in
/// flight, which is how long the screen could not answer a touch. It pings the main queue from a
/// utility queue every `interval` and times each ping's wait.
final class MainThreadWatchdog: Sendable {
    nonisolated static let interval: Duration = .milliseconds(50)

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
    private let timer: any DispatchSourceTimer

    init() {
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        let interval = DispatchTimeInterval.milliseconds(Self.interval.wholeMilliseconds)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.ping() }
        timer.resume()
    }

    deinit {
        timer.cancel()
    }

    /// The longest wait so far, counting a ping still waiting. The watchdog stops pinging.
    func stop() -> Duration {
        timer.cancel()
        return state.withLock { state in
            state.waited(until: .now)
            return state.longest
        }
    }

    private func ping() {
        let isWaiting = state.withLock { state in
            let now = ContinuousClock.now
            state.waited(until: now)
            guard state.waitingSince == nil else { return true }
            state.waitingSince = now
            return false
        }
        guard !isWaiting else { return }
        DispatchQueue.main.async { [weak self] in
            self?.state.withLock { state in
                state.waited(until: .now)
                state.waitingSince = nil
            }
        }
    }
}
