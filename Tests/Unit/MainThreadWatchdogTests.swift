import Foundation
import Synchronization
import Testing

@testable import WorkoutTracker

/// The main queue and the clock as a test holds them. A ping waits until the test runs it, and
/// time moves only when the test advances it.
private final class HeldMainThread: Sendable {
    private let start = ContinuousClock.now
    private let elapsed = Mutex(Duration.zero)
    private let pings = Mutex<[@Sendable () -> Void]>([])

    var now: ContinuousClock.Instant {
        start + elapsed.withLock { $0 }
    }

    var queued: Int {
        pings.withLock { $0.count }
    }

    func watchdog() -> MainThreadWatchdog {
        MainThreadWatchdog(clock: { self.now }, mainQueue: { ping in self.pings.withLock { $0.append(ping) } })
    }

    func advance(by duration: Duration) {
        elapsed.withLock { $0 += duration }
    }

    /// Runs the oldest queued ping, as the main thread does when it is free.
    func runNextPing(sourceLocation: SourceLocation = #_sourceLocation) {
        guard let ping = pings.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
            Issue.record("No ping reached the main queue", sourceLocation: sourceLocation)
            return
        }
        ping()
    }
}

@Test func anIdleMainThreadReportsOnlyHowLongEachPingWaited() {
    let main = HeldMainThread()
    let watchdog = main.watchdog()

    for _ in 0..<10 {
        main.advance(by: .milliseconds(50))
        watchdog.ping()
        main.advance(by: .milliseconds(2))
        main.runNextPing()
    }
    main.advance(by: .milliseconds(300))

    #expect(watchdog.stop() == .milliseconds(2))
}

@Test func aHeldMainThreadIsTheLongestStallAndHoldsOnePing() {
    let main = HeldMainThread()
    let watchdog = main.watchdog()

    main.advance(by: .milliseconds(50))
    watchdog.ping()
    for _ in 0..<6 {
        main.advance(by: .milliseconds(50))
        watchdog.ping()
    }
    #expect(main.queued == 1)
    main.advance(by: .milliseconds(30))
    main.runNextPing()
    main.advance(by: .milliseconds(50))
    watchdog.ping()
    main.advance(by: .milliseconds(2))
    main.runNextPing()

    #expect(watchdog.stop() == .milliseconds(330))
}

@Test func aStallStillUnderwayWhenTheWatchdogStopsCounts() {
    let main = HeldMainThread()
    let watchdog = main.watchdog()

    main.advance(by: .milliseconds(50))
    watchdog.ping()
    main.advance(by: .milliseconds(2))
    main.runNextPing()
    main.advance(by: .milliseconds(50))
    watchdog.ping()
    main.advance(by: .milliseconds(400))

    #expect(watchdog.stop() == .milliseconds(400))
}

// aMainThreadHeldBusyIsTheLongestStall drives the real timer and main queue on purpose, and asserts
// only a floor. It still fails when repeated in one process (#1096).
// swiftlint:disable tests_wait_on_events_not_clocks
@MainActor
private func holdTheMainThread(for seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}

/// The real timer and main queue. It asserts only a floor, because a loaded machine stalls the
/// main thread longer, never shorter.
@MainActor
@Test func aMainThreadHeldBusyIsTheLongestStall() async {
    let watchdog = MainThreadWatchdog()
    try? await Task.sleep(for: MainThreadWatchdog.interval * 2)

    holdTheMainThread(for: 0.3)
    try? await Task.sleep(for: MainThreadWatchdog.interval)

    #expect(watchdog.stop() >= .milliseconds(200))
}
// swiftlint:enable tests_wait_on_events_not_clocks
