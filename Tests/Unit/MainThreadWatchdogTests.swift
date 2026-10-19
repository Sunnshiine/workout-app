import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func holdTheMainThread(for seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}

/// Only a floor: a loaded machine stalls the main thread longer, never shorter.
@MainActor
@Test func aMainThreadHeldBusyIsTheLongestStall() async {
    let watchdog = MainThreadWatchdog()
    try? await Task.sleep(for: MainThreadWatchdog.interval * 2)

    holdTheMainThread(for: 0.3)
    try? await Task.sleep(for: MainThreadWatchdog.interval)

    #expect(watchdog.stop() >= .milliseconds(200))
}

@MainActor
@Test func aStallStillUnderwayWhenTheWatchdogStopsCounts() async {
    let watchdog = MainThreadWatchdog()
    try? await Task.sleep(for: MainThreadWatchdog.interval * 2)

    holdTheMainThread(for: 0.3)

    #expect(watchdog.stop() >= .milliseconds(200))
}
