import Foundation
import Testing

enum TestsWaitOnEventsNotClocks {
    static func taskSleepIsFlagged() async throws {
        try await Task.sleep(for: .milliseconds(10))
    }

    static func continuousClockIsFlagged() -> ContinuousClock {
        ContinuousClock()
    }

    static func suspendingClockIsFlagged() -> SuspendingClock {
        SuspendingClock()
    }

    static func continuousClockDeadlineIsFlagged() -> ContinuousClock.Instant {
        ContinuousClock.now + .seconds(10)
    }

    static func suspendingClockComparisonIsFlagged(deadline: SuspendingClock.Instant) -> Bool {
        SuspendingClock.now < deadline
    }

    @Test(.timeLimit(.minutes(1))) static func timeLimitIsFlagged() {}

    static func threadSleepIsFlagged() {
        Thread.sleep(forTimeInterval: 0.1)
    }

    static func usleepIsFlagged() {
        usleep(1_000)
    }

    static func asyncAfterIsFlagged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {}
    }

    static func measureIsFlagged(clock: some Clock<Duration>) async -> Duration {
        await clock.measure {}
    }

    static func measureWithParenthesesIsFlagged(clock: some Clock<Duration>) async -> Duration {
        await clock.measure({})
    }

    static func deadlineAdvancedFromNowIsFlagged() -> ContinuousClock.Instant {
        ContinuousClock.now.advanced(by: .seconds(1))
    }

    static func genericTaskSleepIsFlagged() async throws {
        try await Task<Never, Never>.sleep(for: .seconds(1))
    }

    static func bareSleepIsFlagged() {
        sleep(1)
    }

    static func nanosleepIsFlagged() {
        nanosleep(nil, nil)
    }

    static func semaphoreTimeoutIsFlagged() -> DispatchTimeoutResult {
        DispatchSemaphore(value: 0).wait(timeout: .distantFuture)
    }

    static func dispatchTimeNowIsFlagged() -> DispatchTime {
        DispatchTime.now()
    }

    static func absoluteTimeIsFlagged() -> CFAbsoluteTime {
        CFAbsoluteTimeGetCurrent()
    }

    static func systemUptimeIsFlagged() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    static func scheduledTimerIsFlagged() -> Timer {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in }
    }

    static func nowOnAClockInstanceIsMissed(clock: ContinuousClock) -> ContinuousClock.Instant {
        clock.now
    }

    static func sleepOnAnInjectedRealClockIsMissed(clock: some Clock<Duration>) async throws {
        try await clock.sleep(for: .seconds(1))
    }

    static func instantTypePasses(at instant: ContinuousClock.Instant) -> ContinuousClock.Instant {
        instant
    }

    static func clockInACommentPasses() {
        // try await Task.sleep(for: .seconds(1))
    }

    static func clockInADocCommentPasses() {
        /// ContinuousClock().measure { }
    }

    static func clockInAStringPasses() -> String {
        "Thread.sleep(forTimeInterval: 1)"
    }
}
