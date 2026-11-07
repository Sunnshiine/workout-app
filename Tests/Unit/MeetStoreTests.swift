import Foundation
import Testing

@testable import WorkoutTracker

@Suite("A Meet on the phone")
@MainActor
struct MeetStoreTests {
    private let defaults = AppDefaults.inMemory()
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_796_558_400)
    }
    private let clock = Clock()

    private func store() -> MeetStore {
        let clock = clock
        return MeetStore(defaults: defaults, now: { clock.date })
    }

    private func planned() throws -> MeetStore {
        let store = store()
        var meet = Meet(date: try #require(MeetDate("2026-12-05")), federation: .ipf)
        meet.liftersInFlight = 10
        meet.editLift(.squat) { edit in
            edit.enter(Kilograms(whole: 180), at: .opener)
            edit.enter(Kilograms(whole: 190), at: .second)
        }
        store.start(meet)
        return store
    }

    @Test func aRelaunchFindsTheWindowStillRunningFromTheLights() throws {
        let store = try planned()
        store.setAttemptsOut(0)
        try store.mark(.good)

        clock.date.addTimeInterval(50)
        let relaunched = self.store()

        guard case .window(let window) = relaunched.meet?.stage(at: relaunched.now()) else {
            Issue.record("the window did not survive the relaunch")
            return
        }
        #expect(window.reading == .closing(secondsLeft: 10))
        #expect(window.tableEntry == Kilograms(hundredths: 18250))
    }

    @Test func undoTakesBackTheMarkAndItsWindow() throws {
        let store = try planned()
        store.setAttemptsOut(0)
        try store.mark(.noLift)
        #expect(store.canUndoMark)

        store.undoMark()

        #expect(!store.canUndoMark)
        #expect(store.meet?.attemptWindow == nil)
        #expect(store.meet?.lift(.squat).attempts[0].state == .planned)
        #expect(store.meet?.countedAttemptsOut == 0)
    }

    @Test func theNextGestureEndsTheChanceToUndo() throws {
        let store = try planned()
        store.setAttemptsOut(0)
        try store.mark(.good)
        try store.submitNext(Kilograms(whole: 190))
        #expect(!store.canUndoMark)
        store.undoMark()
        #expect(store.meet?.lift(.squat).attempts[0].state == .good)
    }

    @Test func anExpiredWindowOverwritesNothingUntilTheAthleteAnswers() throws {
        let store = try planned()
        store.setAttemptsOut(0)
        try store.mark(.good)
        clock.date.addTimeInterval(120)

        #expect(store.meet?.lift(.squat).attempts[1].kilograms == Kilograms(whole: 190))
        #expect(store.meet?.attemptWindow != nil)

        try store.acceptTableEntry()

        #expect(store.meet?.lift(.squat).attempts[1].kilograms == Kilograms(hundredths: 18250))
        #expect(store.meet?.attemptWindow == nil)
    }

    @Test func deletingLeavesNoMeetForARelaunch() throws {
        let store = try planned()
        store.delete()
        #expect(store.meet == nil)
        #expect(self.store().meet == nil)
    }

    @Test func anUnreadableRecordLeavesNoMeetRatherThanStoppingTheApp() {
        defaults.set("not json", forKey: "meetRecord")
        #expect(store().meet == nil)
    }
}
