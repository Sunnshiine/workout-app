import Foundation
import Testing

@testable import WorkoutTracker

private let opener = Kilograms(whole: 180)
private let plan = [
    WarmupRoomStep(kilograms: Kilograms(whole: 60), reps: 5, attemptsOut: 18),
    WarmupRoomStep(kilograms: Kilograms(whole: 140), reps: 3, attemptsOut: 6),
    WarmupRoomStep(kilograms: Kilograms(whole: 165), reps: 1, attemptsOut: 3)
]

private func cue(_ attemptsOut: Int, warmups: [WarmupRoomStep] = plan, secondsPerAttempt: Int = 60) -> MeetCue {
    MeetClock.cue(attemptsOut: attemptsOut, secondsPerAttempt: secondsPerAttempt, warmups: warmups, attempt: opener)
}

@Suite("MeetClock")
struct MeetClockTests {
    @Test("Far out, the next step is the plan's first, and the wait counts to it")
    func farOutTheFirstStepIsNext() {
        #expect(cue(20) == .warmUp(plan[0], attemptsUntil: 2, secondsUntil: 120))
    }

    @Test("On a step's own count the step is due now")
    func onItsCountAStepIsDue() {
        #expect(cue(6) == .warmUp(plan[1], attemptsUntil: 0, secondsUntil: 0))
    }

    @Test("Past a step's count the next one down is next")
    func pastACountTheNextStepIsNext() {
        #expect(cue(5) == .warmUp(plan[2], attemptsUntil: 2, secondsUntil: 120))
    }

    @Test("Below the last step the athlete waits for the platform")
    func belowTheLastStepTheAthleteWaits() {
        #expect(cue(2) == .attempt(opener, attemptsOut: 2, secondsUntil: 120))
    }

    @Test("At zero the athlete is on the platform, whatever the plan holds")
    func atZeroTheAthleteIsOnThePlatform() {
        #expect(cue(0) == .platform(opener))
        #expect(cue(0, warmups: []) == .platform(opener))
    }

    @Test("With no plan the day only counts to the platform")
    func withNoPlanTheDayCounts() {
        #expect(cue(7, warmups: []) == .attempt(opener, attemptsOut: 7, secondsUntil: 420))
    }

    @Test("The time is the athlete's own Seconds per Attempt")
    func theTimeIsTheAthletesSecondsPerAttempt() {
        #expect(cue(7, warmups: [], secondsPerAttempt: 45) == .attempt(opener, attemptsOut: 7, secondsUntil: 315))
    }
}

@Suite("Attempt Window")
struct AttemptWindowTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)
    private var window: AttemptWindow { AttemptWindow(lift: .squat, startedAt: start, seconds: 60) }

    @Test(
        "It reads open, then closing for the last 15 seconds, then expired",
        arguments: [
            (0, AttemptWindow.Reading.open(secondsLeft: 60)),
            (1, .open(secondsLeft: 59)),
            (44, .open(secondsLeft: 16)),
            (45, .closing(secondsLeft: 15)),
            (59, .closing(secondsLeft: 1)),
            (60, .expired),
            (3_600, .expired)
        ]
    )
    func itReadsAtEachSecond(elapsed: Int, reading: AttemptWindow.Reading) {
        #expect(window.reading(at: start.addingTimeInterval(TimeInterval(elapsed))) == reading)
    }

    @Test("A clock set back never reads more than the minute")
    func aClockSetBackReadsTheFullMinute() {
        #expect(window.reading(at: start.addingTimeInterval(-30)) == .open(secondsLeft: 60))
    }
}

@Suite("Warm-up Room Plan fill")
struct WarmupRoomPlanFillTests {
    private let multiple = Kilograms(hundredths: 250)

    @Test("Even steps climb from the empty bar, on the bar's multiple, and stop short of the opener")
    func evenStepsClimbToTheOpener() {
        let steps = WarmupRoomPlanFill.evenSteps(toOpener: Kilograms(whole: 180), barMultiple: multiple)
        #expect(steps.map(\.kilograms.numeral) == ["20", "45", "72.5", "100", "125", "152.5"])
        #expect(steps.map(\.attemptsOut) == [18, 15, 12, 9, 6, 3])
    }

    @Test("A light opener drops the steps rounding would repeat")
    func aLightOpenerDropsRepeats() {
        let steps = WarmupRoomPlanFill.evenSteps(toOpener: Kilograms(whole: 25), barMultiple: multiple)
        #expect(steps.map(\.kilograms.numeral) == ["20", "22.5"])
    }

    @Test("An opener at the bar has nothing below it to warm up with")
    func anOpenerAtTheBarHasNoSteps() {
        #expect(WarmupRoomPlanFill.evenSteps(toOpener: Kilograms(whole: 20), barMultiple: multiple).isEmpty)
    }
}
