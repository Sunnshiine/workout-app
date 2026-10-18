import Foundation
import Testing

@testable import WorkoutTracker

private let rest = LiveActivityRestContent(
    exerciseName: "Back Squat",
    prescribedReps: "5",
    prescribedLoad: "RPE 7",
    weightValue: "235",
    weightUnit: "lbs",
    setsDone: 1,
    setsTotal: 3,
    variant: .restTimerSetsLeft,
    restStartDate: Date(timeIntervalSince1970: 1_780_000_000),
    restEndDate: Date(timeIntervalSince1970: 1_780_000_180)
)

@Test func withNoActivityUpAReadbackStartsOneAndAFinalOneEndsItShowingTheResult() {
    let listening = LiveActivityReadbackPlan.plan(isFinal: false, owner: .nobody, activityIsUp: false) { _ in true }
    #expect(listening == LiveActivityReadbackPlan(canvas: .alone, steps: [.start], owner: .dictation))

    let result = LiveActivityReadbackPlan.plan(isFinal: true, owner: .nobody, activityIsUp: false) { _ in true }
    #expect(result == LiveActivityReadbackPlan(canvas: .alone, steps: [.start, .endShowing], owner: .nobody))
}

@Test func aReadbackRidesTheRunningRestAndLeavesItTheActivity() {
    for isFinal in [false, true] {
        let plan = LiveActivityReadbackPlan.plan(isFinal: isFinal, owner: .rest(rest), activityIsUp: true) { $0 == rest }
        #expect(plan == LiveActivityReadbackPlan(canvas: .overRest(rest), steps: [.update], owner: .rest(rest)))
    }
}

/// A write used up the rest that led to its Set, so its readback takes the activity and ends it.
@Test func aReadbackThatMayNotRideTheRestTakesTheActivityAsItsOwn() {
    let listening = LiveActivityReadbackPlan.plan(isFinal: false, owner: .rest(rest), activityIsUp: true) { _ in false }
    #expect(listening == LiveActivityReadbackPlan(canvas: .alone, steps: [.update], owner: .dictation))

    let result = LiveActivityReadbackPlan.plan(isFinal: true, owner: .rest(rest), activityIsUp: true) { _ in false }
    #expect(result == LiveActivityReadbackPlan(canvas: .alone, steps: [.endShowing], owner: .nobody))
}

/// An activity up that nobody here owns, left by an earlier process, is taken over like one
/// started for the readback, so a final readback ends it instead of staying up for good.
@Test(arguments: [LiveActivityOwner.dictation, .nobody])
func anActivityOfTheReadbacksOwnOrOfNobodysUpdatesAndEndsOnTheResult(owner: LiveActivityOwner) {
    let listening = LiveActivityReadbackPlan.plan(isFinal: false, owner: owner, activityIsUp: true) { _ in true }
    #expect(listening == LiveActivityReadbackPlan(canvas: .alone, steps: [.update], owner: .dictation))

    let result = LiveActivityReadbackPlan.plan(isFinal: true, owner: owner, activityIsUp: true) { _ in true }
    #expect(result == LiveActivityReadbackPlan(canvas: .alone, steps: [.endShowing], owner: .nobody))
}

@Test func withdrawingAReadbackRestoresARunningRestAndEndsAnActivityOfItsOwn() {
    #expect(LiveActivityReadbackWithdrawal.plan(owner: .rest(rest), activityIsUp: true) == .restoreRest(rest))
    #expect(LiveActivityReadbackWithdrawal.plan(owner: .rest(rest), activityIsUp: false) == .nothing)
    #expect(LiveActivityReadbackWithdrawal.plan(owner: .dictation, activityIsUp: true) == .end)
    #expect(LiveActivityReadbackWithdrawal.plan(owner: .nobody, activityIsUp: true) == .end)
}
