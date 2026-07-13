import Foundation
import Testing

@testable import WorkoutTracker

// The rest module — not the pill — owns which haptic events are due on a tick. These tests pin
// the final-five taps, the single expiry buzz, scene-phase suppression, no duplicates, and the
// restart reset, so the pill can become a pure renderer that just plays what the module surfaces.

@MainActor
private func startedTimer(duration: TimeInterval, at start: Date) -> (RestTimer, ManualEmissionClock) {
    let clock = ManualEmissionClock(now: start)
    let timer = RestTimer(clock: clock)
    timer.start(duration: duration, origin: ActiveSetID(exerciseOrder: 1, setIndex: 0))
    return (timer, clock)
}

@MainActor
private final class ManualEmissionClock: RestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now.addTimeInterval(seconds)
    }
}

@MainActor
@Test func restModuleSurfacesNoHapticsOnTheFirstTick() {
    let (timer, _) = startedTimer(duration: 120, at: Date(timeIntervalSinceReferenceDate: 0))

    // No previous elapsed to advance from yet, so the first tick surfaces nothing.
    #expect(timer.dueHapticEvents(at: Date(timeIntervalSinceReferenceDate: 0), sceneActive: true).isEmpty)
}

@MainActor
@Test func restModuleSurfacesEachFinalFiveTapExactlyOnce() {
    let (timer, clock) = startedTimer(duration: 120, at: Date(timeIntervalSinceReferenceDate: 0))

    _ = timer.dueHapticEvents(at: clock.now, sceneActive: true) // seed previous elapsed = 0

    var surfaced: [RestHapticEvent] = []
    for _ in 0..<120 {
        clock.advance(by: 1)
        surfaced += timer.dueHapticEvents(at: clock.now, sceneActive: true)
    }

    #expect(
        surfaced == [
            RestHapticEvent(offset: 115, kind: .lightTap),
            RestHapticEvent(offset: 116, kind: .lightTap),
            RestHapticEvent(offset: 117, kind: .lightTap),
            RestHapticEvent(offset: 118, kind: .lightTap),
            RestHapticEvent(offset: 119, kind: .lightTap),
            RestHapticEvent(offset: 120, kind: .expiryBuzz)
        ]
    )
}

@MainActor
@Test func restModuleSuppressesTapsWhenSceneInactiveWithoutReplayingThem() {
    let (timer, clock) = startedTimer(duration: 120, at: Date(timeIntervalSinceReferenceDate: 0))

    _ = timer.dueHapticEvents(at: clock.now, sceneActive: true) // previous elapsed = 0

    clock.advance(by: 116)
    // Backgrounded: the 115 and 116 taps come due but are suppressed…
    #expect(timer.dueHapticEvents(at: clock.now, sceneActive: false).isEmpty)

    clock.advance(by: 1)
    // …and are not replayed in a burst when the scene returns to active — only 117 fires.
    #expect(
        timer.dueHapticEvents(at: clock.now, sceneActive: true) == [
            RestHapticEvent(offset: 117, kind: .lightTap)
        ]
    )
}

@MainActor
@Test func restModuleSurfacesTheExpiryBuzzOnlyOnce() {
    let (timer, clock) = startedTimer(duration: 120, at: Date(timeIntervalSinceReferenceDate: 0))

    _ = timer.dueHapticEvents(at: clock.now, sceneActive: true)

    clock.advance(by: 200)
    let atExpiry = timer.dueHapticEvents(at: clock.now, sceneActive: true)
    #expect(atExpiry.contains(RestHapticEvent(offset: 120, kind: .expiryBuzz)))

    clock.advance(by: 5)
    #expect(timer.dueHapticEvents(at: clock.now, sceneActive: true).isEmpty)
}

@MainActor
@Test func restModuleResetsHapticBookkeepingWhenRestRestarts() {
    let (timer, clock) = startedTimer(duration: 120, at: Date(timeIntervalSinceReferenceDate: 0))

    _ = timer.dueHapticEvents(at: clock.now, sceneActive: true)
    clock.advance(by: 200)
    _ = timer.dueHapticEvents(at: clock.now, sceneActive: true) // drains every event

    timer.start(duration: 120, origin: ActiveSetID(exerciseOrder: 2, setIndex: 0))

    // A fresh interval starts its bookkeeping over: the first tick surfaces nothing again.
    #expect(timer.dueHapticEvents(at: clock.now, sceneActive: true).isEmpty)
}

@MainActor
@Test func restModuleSurfacesNoHapticsWhenNoRestIsRunning() {
    let clock = ManualEmissionClock(now: Date(timeIntervalSinceReferenceDate: 0))
    let timer = RestTimer(clock: clock)

    #expect(timer.dueHapticEvents(at: clock.now, sceneActive: true).isEmpty)
}
