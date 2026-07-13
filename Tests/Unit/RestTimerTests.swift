import Foundation
import Testing

@testable import WorkoutTracker

#if canImport(UserNotifications)
    import UserNotifications
#endif

@MainActor
private final class ManualRestClock: RestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now.addTimeInterval(seconds)
    }
}

@MainActor
private final class MockRestNotificationScheduler: RestNotificationScheduling {
    private(set) var requestedAuthorizationCount = 0
    private(set) var scheduledDeadlines: [Date] = []
    private(set) var cancelCount = 0

    func requestAuthorizationIfNeeded() {
        requestedAuthorizationCount += 1
    }

    func schedule(deadline: Date) {
        scheduledDeadlines.append(deadline)
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
@Test func restTimerStartSetsDeadlineAndRemainingTracksClock() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))

    #expect(timer.interval?.end == Date(timeIntervalSinceReferenceDate: 1_120))
    #expect(timer.remaining == 120)
    #expect(timer.isRunning)

    clock.advance(by: 45)

    #expect(timer.remaining == 75)
    #expect(timer.isRunning)

    clock.advance(by: 75)

    #expect(timer.remaining == 0)
    #expect(!timer.isRunning)
}

@MainActor
@Test func restTimerStartStoresStandardAndSupersetLabels() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0), kind: .standard)

    #expect(timer.label == "Rest")

    timer.start(duration: 30, origin: ActiveSetID(exerciseOrder: 2, setIndex: 0), kind: .superset)

    #expect(timer.label == "Superset rest")
}

@MainActor
@Test func restTimerSchedulesNotificationAtDeadlineOnStart() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let scheduler = MockRestNotificationScheduler()
    let timer = RestTimer(clock: clock, notificationScheduler: scheduler)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))

    #expect(scheduler.scheduledDeadlines == [Date(timeIntervalSinceReferenceDate: 1_120)])
    #expect(scheduler.cancelCount == 0)
}

@MainActor
@Test func restTimerReschedulesNotificationWhenRestRestarts() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let scheduler = MockRestNotificationScheduler()
    let timer = RestTimer(clock: clock, notificationScheduler: scheduler)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    clock.advance(by: 30)
    timer.start(duration: 180, origin: ActiveSetID(exerciseOrder: 2, setIndex: 0))

    #expect(
        scheduler.scheduledDeadlines == [
            Date(timeIntervalSinceReferenceDate: 1_120),
            Date(timeIntervalSinceReferenceDate: 1_210)
        ]
    )
    #expect(scheduler.cancelCount == 1)
}

@MainActor
@Test func restTimerCancelsNotificationOnDismiss() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let scheduler = MockRestNotificationScheduler()
    let timer = RestTimer(clock: clock, notificationScheduler: scheduler)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    timer.dismiss()

    #expect(scheduler.cancelCount == 1)
}

#if canImport(UserNotifications)
    @Test func restNotificationForegroundPolicySuppressesRestNotification() {
        let restOptions = RestNotificationForegroundPolicy.presentationOptions(
            for: RestNotificationForegroundPolicy.identifier
        )
        let unrelatedOptions = RestNotificationForegroundPolicy.presentationOptions(for: "other-notification")

        #expect(restOptions == [])
        #expect(unrelatedOptions == [.banner, .sound])
    }
#endif

@MainActor
@Test func restTimerDismissClearsActiveRest() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    timer.dismiss()

    #expect(timer.interval == nil)
    #expect(timer.remaining == 0)
    #expect(!timer.isRunning)
}

@MainActor
@Test func restTimerExpireIfNeededClearsOnlyElapsedRest() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    timer.expireIfNeeded(at: Date(timeIntervalSinceReferenceDate: 1_119))

    #expect(timer.interval?.end == Date(timeIntervalSinceReferenceDate: 1_120))

    timer.expireIfNeeded(at: Date(timeIntervalSinceReferenceDate: 1_120))

    #expect(timer.interval == nil)
    #expect(timer.remaining == 0)
    #expect(!timer.isRunning)
}

@MainActor
@Test func restTimerRestartReplacesDeadlineOriginAndAdvancesRestartRevision() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    clock.advance(by: 30)
    timer.start(duration: 180, origin: ActiveSetID(exerciseOrder: 2, setIndex: 1))

    #expect(timer.interval?.end == Date(timeIntervalSinceReferenceDate: 1_210))
    #expect(timer.remaining == 180)
    #expect(timer.origin == ActiveSetID(exerciseOrder: 2, setIndex: 1))
    #expect(timer.restartRevision == 2)
}

@MainActor
@Test func restTimerPublishesRestIntervalRetainingTheComputedStart() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0), kind: .superset)

    let interval = timer.interval
    #expect(interval?.start == Date(timeIntervalSinceReferenceDate: 1_000))
    #expect(interval?.end == Date(timeIntervalSinceReferenceDate: 1_120))
    #expect(interval?.duration == 120)
    #expect(interval?.kind == .superset)
    // The retained start round-trips with remaining back to the end the timer computed.
    #expect(interval.map { $0.start.addingTimeInterval($0.remaining(at: $0.start)) } == interval?.end)
}

@MainActor
@Test func restTimerRemainingReadsThroughThePublishedInterval() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))

    clock.advance(by: 45)

    #expect(timer.remaining == timer.interval?.remaining(at: clock.now))
    #expect(timer.remaining == 75)
}

@MainActor
@Test func restTimerCancelsOnlyMatchingOrigin() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let timer = RestTimer(clock: clock)
    let origin = ActiveSetID(exerciseOrder: 1, setIndex: 0)

    timer.start(duration: 120, origin: origin)
    timer.cancel(ifOriginMatches: ActiveSetID(exerciseOrder: 1, setIndex: 1))

    #expect(timer.isRunning)
    #expect(timer.origin == origin)

    timer.cancel(ifOriginMatches: origin)

    #expect(timer.interval == nil)
    #expect(timer.origin == nil)
    #expect(!timer.isRunning)
}
