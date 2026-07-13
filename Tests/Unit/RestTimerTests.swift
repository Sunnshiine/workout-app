import Foundation
import Testing

@testable import WorkoutTracker

#if canImport(UserNotifications)
    import UserNotifications
#endif

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
private final class MockRestExpiryScheduler: RestExpiryScheduling {
    private(set) var scheduledDeadlines: [Date] = []
    private(set) var cancelCount = 0
    private var expire: (@MainActor () -> Void)?

    func schedule(deadline: Date, expire: @escaping @MainActor () -> Void) {
        scheduledDeadlines.append(deadline)
        self.expire = expire
    }

    func cancel() {
        cancelCount += 1
        expire = nil
    }

    /// Simulate the deadline arriving — the single moment the module decides rest is over.
    func fire() {
        expire?()
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
@Test func restTimerSchedulesSelfExpiryAtDeadlineOnStart() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let expiry = MockRestExpiryScheduler()
    let timer = RestTimer(clock: clock, expiryScheduler: expiry)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))

    #expect(expiry.scheduledDeadlines == [Date(timeIntervalSinceReferenceDate: 1_120)])
    #expect(expiry.cancelCount == 0)
}

// Off-screen case: no pill is ever involved, yet reaching the deadline ends the rest and
// cancels the pending notification exactly once, from RestTimer itself.
@MainActor
@Test func restTimerSelfDrivesExpiryAtDeadlineWithoutAPill() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let scheduler = MockRestNotificationScheduler()
    let expiry = MockRestExpiryScheduler()
    let timer = RestTimer(clock: clock, notificationScheduler: scheduler, expiryScheduler: expiry)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(timer.isRunning)

    clock.advance(by: 120)
    expiry.fire()

    #expect(timer.interval == nil)
    #expect(timer.remaining == 0)
    #expect(!timer.isRunning)
    #expect(scheduler.cancelCount == 1)
}

// Single author: the "rest ended" instant fires once. A stray second fire (or any leftover
// caller) must not clear a fresh rest or double-cancel the notification.
@MainActor
@Test func restTimerExpiresExactlyOnce() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let scheduler = MockRestNotificationScheduler()
    let expiry = MockRestExpiryScheduler()
    let timer = RestTimer(clock: clock, notificationScheduler: scheduler, expiryScheduler: expiry)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    clock.advance(by: 120)
    expiry.fire()
    expiry.fire()

    #expect(timer.interval == nil)
    #expect(scheduler.cancelCount == 1)
}

// A pill is on screen: the deadline-driven expiry must author the expiry buzz and keep the rest
// alive a beat so the (still-mounted) pill can play it, rather than clearing the rest out from
// under the buzz. Regression net for the dropped on-screen expiry buzz.
@MainActor
@Test func restTimerAuthorsExpiryBuzzForATickingPillThenClearsAfterLinger() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let scheduler = MockRestNotificationScheduler()
    let expiry = MockRestExpiryScheduler()
    let timer = RestTimer(clock: clock, notificationScheduler: scheduler, expiryScheduler: expiry)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    // A mounted pill drives the emitter each second up to — but not reaching — the deadline, so the
    // buzz is still pending when the scheduler expires the rest.
    _ = timer.dueHapticEvents(at: clock.now, sceneActive: true)
    clock.advance(by: 119)
    _ = timer.dueHapticEvents(at: clock.now, sceneActive: true)

    clock.advance(by: 1)
    expiry.fire()

    // The buzz is authored and published; the rest has NOT cleared yet, and no linger-shortening
    // notification cancel has happened.
    #expect(timer.expiryHaptics == [RestHapticEvent(offset: 120, kind: .expiryBuzz)])
    #expect(timer.interval != nil)
    #expect(scheduler.cancelCount == 0)
    #expect(
        expiry.scheduledDeadlines == [
            Date(timeIntervalSinceReferenceDate: 1_120),
            Date(timeIntervalSinceReferenceDate: 1_120.5)
        ]
    )

    // The linger elapses: the rest clears exactly once and the buzz buffer is emptied.
    expiry.fire()
    #expect(timer.interval == nil)
    #expect(timer.expiryHaptics.isEmpty)
    #expect(scheduler.cancelCount == 1)
}

// With no pill ticking, there is nothing to play, so the rest clears immediately at the deadline —
// no buzz is authored and no linger is armed.
@MainActor
@Test func restTimerClearsImmediatelyAtDeadlineWithNoBuzzWhenNoPillTicked() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let expiry = MockRestExpiryScheduler()
    let timer = RestTimer(clock: clock, expiryScheduler: expiry)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    clock.advance(by: 120)
    expiry.fire()

    #expect(timer.expiryHaptics.isEmpty)
    #expect(timer.interval == nil)
    #expect(expiry.scheduledDeadlines == [Date(timeIntervalSinceReferenceDate: 1_120)])
}

// If a haptic tick already surfaced the buzz, the deadline-driven expiry must not re-emit it (no
// duplicate) and clears immediately since there is nothing left to play.
@MainActor
@Test func restTimerDoesNotReauthorTheBuzzWhenATickAlreadySurfacedIt() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let expiry = MockRestExpiryScheduler()
    let timer = RestTimer(clock: clock, expiryScheduler: expiry)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    _ = timer.dueHapticEvents(at: clock.now, sceneActive: true)
    clock.advance(by: 120)
    let surfaced = timer.dueHapticEvents(at: clock.now, sceneActive: true)
    #expect(surfaced.contains(RestHapticEvent(offset: 120, kind: .expiryBuzz)))

    expiry.fire()

    #expect(timer.expiryHaptics.isEmpty)
    #expect(timer.interval == nil)
}

// A stray expiry re-delivery mid-linger must not re-author the buzz or shorten the linger.
@MainActor
@Test func restTimerLingersIdempotentlyWhenExpiryIsRedelivered() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let expiry = MockRestExpiryScheduler()
    let timer = RestTimer(clock: clock, expiryScheduler: expiry)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    _ = timer.dueHapticEvents(at: clock.now, sceneActive: true)
    clock.advance(by: 119)
    _ = timer.dueHapticEvents(at: clock.now, sceneActive: true)
    clock.advance(by: 1)
    expiry.fire()
    let publishedBuzz = timer.expiryHaptics

    timer.expireIfNeeded(at: clock.now)

    #expect(timer.expiryHaptics == publishedBuzz)
    #expect(timer.interval != nil)
}

@MainActor
@Test func restTimerReschedulesSelfExpiryWhenRestRestarts() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let expiry = MockRestExpiryScheduler()
    let timer = RestTimer(clock: clock, expiryScheduler: expiry)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    clock.advance(by: 30)
    timer.start(duration: 180, origin: ActiveSetID(exerciseOrder: 2, setIndex: 0))

    #expect(
        expiry.scheduledDeadlines == [
            Date(timeIntervalSinceReferenceDate: 1_120),
            Date(timeIntervalSinceReferenceDate: 1_210)
        ]
    )
}

@MainActor
@Test func restTimerCancelsScheduledExpiryOnDismiss() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let expiry = MockRestExpiryScheduler()
    let timer = RestTimer(clock: clock, expiryScheduler: expiry)

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    timer.dismiss()

    #expect(expiry.cancelCount == 1)
}

@MainActor
@Test func restTimerCancelsScheduledExpiryWhenOriginMatchesCancel() {
    let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let expiry = MockRestExpiryScheduler()
    let timer = RestTimer(clock: clock, expiryScheduler: expiry)
    let origin = ActiveSetID(exerciseOrder: 1, setIndex: 0)

    timer.start(duration: 120, origin: origin)
    timer.cancel(ifOriginMatches: origin)

    #expect(timer.interval == nil)
    #expect(expiry.cancelCount == 1)
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
