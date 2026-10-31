import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private struct CountdownHarness {
    let time: SteppedCountdownTime
    let cues: RecordingCountdownCues
    let countdown: EffortCountdown

    init() {
        let clock = ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        time = SteppedCountdownTime(clock: clock)
        cues = RecordingCountdownCues(clock: clock)
        countdown = EffortCountdown(clock: clock, scheduler: time, cues: cues)
    }

    var phase: CountdownPhase? {
        countdown.run?.phase(at: time.clock.now)
    }
}

private let owner = CountdownRun.Owner(
    session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
    set: ActiveSetID(exerciseOrder: 1, setIndex: 0)
)

@MainActor
private func seconds(_ seconds: Int) throws -> EffortDuration {
    try #require(EffortDuration("\(seconds) sec"))
}

@MainActor
@Test func anOpeningHoldCountsTheLeadInThenTheHoldAndSaysWhenItIsDone() throws {
    let harness = CountdownHarness()

    harness.countdown.start(.openingHold(try seconds(10)), for: owner)
    harness.time.advance(by: 30)

    #expect(harness.cues.spoken == ["5", "4", "3", "2", "1", "Hold", "3", "2", "1", "Done"])
    #expect(harness.cues.seconds == [0, 1, 2, 3, 4, 5, 12, 13, 14, 15])
    #expect(harness.cues.silences == 0)
}

@MainActor
@Test func aTimedSetSaysGoAndTime() throws {
    let harness = CountdownHarness()

    harness.countdown.start(.timedSet(try seconds(40)), for: owner)
    harness.time.advance(by: 60)

    #expect(harness.cues.spoken == ["5", "4", "3", "2", "1", "Go", "3", "2", "1", "Time"])
    #expect(harness.cues.seconds == [0, 1, 2, 3, 4, 5, 42, 43, 44, 45])
}

@MainActor
@Test(
    "An effort shorter than the closing count closes only on the seconds it reaches",
    arguments: [(1, [String]()), (2, ["1"]), (3, ["2", "1"]), (4, ["3", "2", "1"])]
)
func anEffortShorterThanTheClosingCountClosesOnTheSecondsItReaches(effortSeconds: Int, closing: [String]) throws {
    let harness = CountdownHarness()

    harness.countdown.start(.timedSet(try seconds(effortSeconds)), for: owner)
    harness.time.advance(by: 30)

    #expect(harness.cues.spoken == ["5", "4", "3", "2", "1", "Go"] + closing + ["Time"])
}

@MainActor
@Test func eachCueIsFeltAsWellAsSpoken() throws {
    let hold = TimedEffort.openingHold(try seconds(10))

    #expect(CountdownCue.leadIn(5).haptic == .rest(.lightTap))
    #expect(CountdownCue.begins(hold).haptic == .input(Theme.Haptics.effortBegins))
    #expect(CountdownCue.closing(3).haptic == .rest(.lightTap))
    #expect(CountdownCue.ends(hold).haptic == .rest(.expiryBuzz))
}

@MainActor
@Test func theCountdownShowsTheLeadInThenTheEffortsSecondsLeftThenItsEnd() throws {
    let harness = CountdownHarness()
    harness.countdown.start(.openingHold(try seconds(10)), for: owner)
    var phases: [CountdownPhase?] = []
    let steps: [TimeInterval] = [0, 0.75, 3.25, 1, 0.5, 9, 0.5, 2]

    for step in steps {
        harness.time.advance(by: step)
        phases.append(harness.phase)
    }

    #expect(
        phases == [
            .leadIn(secondsLeft: 5),
            .leadIn(secondsLeft: 5),
            .leadIn(secondsLeft: 1),
            .effort(secondsLeft: 10, elapsedFraction: 0),
            .effort(secondsLeft: 10, elapsedFraction: 0),
            .effort(secondsLeft: 1, elapsedFraction: 0.9),
            .finished,
            nil
        ]
    )
}

@MainActor
@Test func theFinishedCountdownStaysOnTheCardForItsLingerThenClears() throws {
    let harness = CountdownHarness()
    harness.countdown.start(.openingHold(try seconds(10)), for: owner)

    harness.time.advance(by: 15 + EffortCountdown.finishedLinger - 0.25)
    #expect(harness.phase == .finished)

    harness.time.advance(by: 0.25)
    #expect(harness.countdown.run == nil)
    #expect(harness.cues.silences == 0)
}

@MainActor
@Test func cancellingMidHoldSilencesItAndNothingMoreIsSaid() throws {
    let harness = CountdownHarness()
    harness.countdown.start(.openingHold(try seconds(10)), for: owner)
    harness.time.advance(by: 7)

    harness.countdown.cancel()
    harness.time.ring()
    harness.time.advance(by: 30)

    #expect(harness.countdown.run == nil)
    #expect(harness.cues.spoken == ["5", "4", "3", "2", "1", "Hold"])
    #expect(harness.cues.silences == 1)
}

@MainActor
@Test func cancellingWithNoCountdownRunningSilencesNothing() {
    let harness = CountdownHarness()

    harness.countdown.cancel()

    #expect(harness.cues.silences == 0)
}

@MainActor
@Test func aCountdownThatWakesLateSaysOnlyWhereItIsNow() throws {
    let harness = CountdownHarness()
    harness.countdown.start(.openingHold(try seconds(10)), for: owner)

    harness.time.clock.advance(by: 8)
    harness.time.ring()

    #expect(harness.cues.spoken == ["5", "Hold"])
    #expect(harness.cues.seconds == [0, 8])
}

@MainActor
@Test func aWakeWithNothingDueSaysNothingAndKeepsTime() throws {
    let harness = CountdownHarness()
    harness.countdown.start(.openingHold(try seconds(10)), for: owner)

    harness.time.ring()
    harness.time.ring()
    harness.time.advance(by: 30)

    #expect(harness.cues.spoken == ["5", "4", "3", "2", "1", "Hold", "3", "2", "1", "Done"])
    #expect(harness.cues.seconds == [0, 1, 2, 3, 4, 5, 12, 13, 14, 15])
}

@MainActor
@Test func startingAgainSilencesTheCountdownRunningAndCountsFromTheTop() throws {
    let harness = CountdownHarness()
    harness.countdown.start(.openingHold(try seconds(10)), for: owner)
    harness.time.advance(by: 6)

    harness.countdown.start(.timedSet(try seconds(40)), for: owner)

    #expect(harness.cues.silences == 1)
    #expect(harness.phase == .leadIn(secondsLeft: 5))
    #expect(harness.cues.spoken.suffix(2) == ["Hold", "5"])
}
