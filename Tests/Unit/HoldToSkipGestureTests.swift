import Foundation
import Testing

@testable import WorkoutTracker

private let pressStart = ContinuousClock.now

private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
    pressStart + .milliseconds(milliseconds)
}

@Test func holdToSkipGestureRevealsProgressAt250Milliseconds() {
    var gesture = HoldToSkipGesture()
    _ = gesture.pressBegan(at: at(0), policy: .forSet(in: .pending))

    #expect(gesture.nextDeadline == at(250))
    #expect(gesture.deadlineReached(at: at(249)) == [])
    #expect(gesture.deadlineReached(at: at(250)) == [.progress(to: 1, over: 0.6, linear: true)])
}

@Test(arguments: [(SetState.pending, 850), (.logged, 900), (.skipped, 1_100)])
func holdToSkipGestureCommitsAtTheSetStatesHold(state: SetState, commitMilliseconds: Int) {
    var gesture = HoldToSkipGesture()
    _ = gesture.pressBegan(at: at(0), policy: .forSet(in: state))
    _ = gesture.deadlineReached(at: at(250))

    #expect(gesture.nextDeadline == at(commitMilliseconds))
    #expect(gesture.deadlineReached(at: at(commitMilliseconds - 1)) == [])
    #expect(gesture.deadlineReached(at: at(commitMilliseconds)) == [.skip])
}

@Test func holdToSkipGestureReleasedBeforeCommitRetreatsAndSwallowsTheTap() {
    var gesture = HoldToSkipGesture()
    _ = gesture.pressBegan(at: at(0), policy: .forSet(in: .pending))
    _ = gesture.deadlineReached(at: at(250))

    #expect(gesture.pressEnded(at: at(500)) == [.progress(to: 0, over: 0.2, linear: false)])
    #expect(gesture.nextDeadline == nil)
    #expect(gesture.tapped(at: at(520)) == [])
    #expect(gesture.tapped(at: at(1_000)) == [.log])
}

@Test func holdToSkipGestureKeepsThePolicyItsPressBeganWith() {
    var gesture = HoldToSkipGesture()
    _ = gesture.pressBegan(at: at(0), policy: .forSet(in: .pending))
    _ = gesture.deadlineReached(at: at(250))
    _ = gesture.pressBegan(at: at(300), policy: .forSet(in: .skipped))

    #expect(gesture.deadlineReached(at: at(850)) == [.skip])
    #expect(gesture.pressEnded(at: at(900)) == [])

    _ = gesture.pressBegan(at: at(2_000), policy: .forSet(in: .skipped))
    _ = gesture.deadlineReached(at: at(2_250))
    #expect(gesture.deadlineReached(at: at(2_850)) == [])
    #expect(gesture.deadlineReached(at: at(3_100)) == [.skip])
}

@Test func holdToSkipGestureOnANewCardDoesNotInheritTheOldHold() {
    var oldCard = HoldToSkipGesture()
    _ = oldCard.pressBegan(at: at(0), policy: .forSet(in: .pending))
    var newCard = HoldToSkipGesture()

    #expect(newCard.nextDeadline == nil)
    #expect(newCard.deadlineReached(at: at(850)) == [])
    #expect(oldCard.deadlineReached(at: at(850)) == [.skip])
}

@Test func holdToSkipGestureIgnoresTheReleaseAfterACommitAndSwallowsTheNextTap() {
    var gesture = HoldToSkipGesture()
    _ = gesture.pressBegan(at: at(0), policy: .forSet(in: .pending))

    #expect(gesture.deadlineReached(at: at(850)) == [.skip])
    #expect(gesture.pressEnded(at: at(2_000)) == [])
    #expect(gesture.tapped(at: at(2_100)) == [])
    #expect(gesture.tapped(at: at(2_200)) == [.log])
}

@Test func holdToSkipGestureSwallowsTheTapRightAfterAnAccessibilitySkip() {
    var gesture = HoldToSkipGesture()

    #expect(gesture.skipRequested(at: at(0)) == [.skip])
    #expect(gesture.tapped(at: at(20)) == [])
    #expect(gesture.tapped(at: at(300)) == [.log])
    #expect(gesture.pressBegan(at: at(400), policy: .forSet(in: .skipped)) == [.progress(to: 0, over: 0, linear: true)])
}

@Test func holdToSkipGestureStartsNoNewHoldUntilTheSkippingFingerLifts() {
    var gesture = HoldToSkipGesture()
    _ = gesture.pressBegan(at: at(0), policy: .forSet(in: .pending))
    _ = gesture.deadlineReached(at: at(850))

    #expect(gesture.pressBegan(at: at(860), policy: .forSet(in: .skipped)) == [])
    #expect(gesture.nextDeadline == nil)
    #expect(gesture.skipRequested(at: at(870)) == [])
    #expect(gesture.pressEnded(at: at(3_000)) == [])
    #expect(gesture.pressBegan(at: at(3_500), policy: .forSet(in: .skipped)) == [.progress(to: 0, over: 0, linear: true)])
}
