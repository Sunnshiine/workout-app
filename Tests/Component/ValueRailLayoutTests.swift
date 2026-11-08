import CoreGraphics
import Testing

@testable import WorkoutTracker

/// A 150pt track of 48pt cells with no spacing, as the rails draw.
private let reps = ValueRailLayout(trackWidth: 150, cellWidth: 48, spacing: 0, count: 100)
private let rpe = ValueRailLayout(trackWidth: 150, cellWidth: 48, spacing: 0, count: 10)

@Test func theOffsetCentresTheSelectedCell() {
    // The first cell's centre is 24pt in, so centring it shifts the strip right by 150/2 − 24 = 51pt.
    #expect(reps.offset(centering: 0) == 51)
    // Index 4 (reps=5) sits 4 strides in: centre = 48*4 + 24 = 216, offset = 75 − 216 = −141.
    #expect(reps.offset(centering: 4) == -141)
    // Spacing widens the stride: stride 44, centre = 44*2 + 20 = 108, offset = 50 − 108 = −58.
    #expect(ValueRailLayout(trackWidth: 100, cellWidth: 40, spacing: 4, count: 10).offset(centering: 2) == -58)
}

@Test func theCentredIndexIsTheOffsetsInverseAndRoundsAtTheHalfStride() {
    #expect(reps.centredIndex(at: reps.offset(centering: 4)) == 4)
    #expect(reps.centredIndex(at: reps.offset(centering: 4) - 23) == 4)
    #expect(reps.centredIndex(at: reps.offset(centering: 4) - 25) == 5)
    #expect(reps.centredIndex(at: reps.offset(centering: 4) + 25) == 3)
}

@Test func theCentredIndexHoldsToTheStripsEnds() {
    #expect(rpe.centredIndex(at: rpe.offset(centering: 0) + 480) == 0)
    #expect(rpe.centredIndex(at: rpe.offset(centering: 9) - 480) == 9)
    #expect(ValueRailLayout(trackWidth: 150, cellWidth: 48, spacing: 0, count: 0).centredIndex(at: 0) == 0)
}

@Test func aDragBetweenTheEndsFollowsTheFingerOneToOne() {
    let anchor = reps.dragAnchor(grabbedAt: reps.offset(centering: 4), translation: 0)

    #expect(reps.draggedOffset(anchor: anchor, translation: -30) == reps.offset(centering: 4) - 30)
    #expect(reps.draggedOffset(anchor: anchor, translation: 96) == reps.offset(centering: 4) + 96)
}

@Test func theAnchorTakesBackTheTravelSpentReachingTheHysteresis() {
    let anchor = reps.dragAnchor(grabbedAt: reps.offset(centering: 4), translation: 12)

    #expect(reps.draggedOffset(anchor: anchor, translation: 12) == reps.offset(centering: 4))
    #expect(reps.draggedOffset(anchor: anchor, translation: 60) == reps.offset(centering: 4) + 48)
}

@Test func pastAnEndTheStripRubberBands() {
    let end = rpe.offset(centering: 0)
    let anchor = rpe.dragAnchor(grabbedAt: end, translation: 0)

    // Apple's band: 100pt of overshoot on a 150pt track draws (100 · 150 · 0.55) / (150 + 55) = 40.2pt.
    #expect(abs(rpe.draggedOffset(anchor: anchor, translation: 100) - (end + 40.24)) < 0.01)
    let far = rpe.draggedOffset(anchor: anchor, translation: 10_000)
    #expect(far > end + 100 && far < end + 150)
    let lastEnd = rpe.offset(centering: 9)
    let pastTheLast = rpe.draggedOffset(anchor: rpe.dragAnchor(grabbedAt: lastEnd, translation: 0), translation: -100)
    #expect(abs(pastTheLast - (lastEnd - 40.24)) < 0.01)
}

@Test func aGrabPastAnEndCarriesOnFromTheFingersTruePosition() {
    let end = rpe.offset(centering: 0)
    let drawn = rpe.draggedOffset(anchor: rpe.dragAnchor(grabbedAt: end, translation: 0), translation: 100)

    let anchor = rpe.dragAnchor(grabbedAt: drawn, translation: 0)

    #expect(abs(anchor - (end + 100)) < 0.01)
    #expect(abs(rpe.draggedOffset(anchor: anchor, translation: -100) - end) < 0.01)
}

@Test func aLiftWithNoSpeedLandsOnTheNearestDetentOnTheReleaseSpring() {
    let landing = reps.landing(liftedAt: reps.offset(centering: 4) - 30, velocity: 0, reducesMotion: false)

    #expect(landing.index == 5)
    #expect(landing.spring == Theme.Gesture.release)
    #expect(landing.initialVelocity == 0)
}

@Test func aThrowLandsOnTheDetentNearestItsProjectedRest() {
    // Apple's projection at rate 0.99 carries 0.099 s of the release speed: 2000 pt/s travels 198pt,
    // four more detents to the left, so the strip lands on index 8.
    let landing = reps.landing(liftedAt: reps.offset(centering: 4), velocity: -2000, reducesMotion: false)

    #expect(landing.index == 8)
    #expect(landing.spring == Theme.Gesture.release)
}

@Test func theSpringIsSeededWithTheReleaseSpeedAsAShareOfTheDistanceLeft() {
    let lifted = reps.offset(centering: 4) - 30
    let landing = reps.landing(liftedAt: lifted, velocity: -120, reducesMotion: false)

    // 120 pt/s projects 11.9pt further, still nearest index 5, 18pt away: 120 / 18 of the way per second.
    #expect(landing.index == 5)
    #expect(abs(landing.initialVelocity - 120 / 18) < 0.001)
    #expect(reps.landing(liftedAt: reps.offset(centering: 4), velocity: 0, reducesMotion: false).initialVelocity == 0)
}

@Test func aThrowHoldsToTheStripsEnds() {
    #expect(rpe.landing(liftedAt: rpe.offset(centering: 8), velocity: -5000, reducesMotion: false).index == 9)
    #expect(rpe.landing(liftedAt: rpe.offset(centering: 1), velocity: 5000, reducesMotion: false).index == 0)
}

@Test func aLiftPastAnEndSnapsBackToTheEndWithNoSeed() {
    let end = rpe.offset(centering: 0)
    let pastTheEnd = rpe.draggedOffset(anchor: rpe.dragAnchor(grabbedAt: end, translation: 0), translation: 100)

    let landing = rpe.landing(liftedAt: pastTheEnd, velocity: 300, reducesMotion: false)

    #expect(landing.index == 0)
    #expect(landing.spring == Theme.Gesture.snapBack)
    #expect(landing.initialVelocity == 0)
}

@Test func aTapOrAVoiceOverStepRecentresOnTheReleaseSpringOrUnderReduceMotionTheSnapBack() {
    #expect(ValueRailLayout.settle(reducesMotion: false) == Theme.Gesture.release)
    #expect(ValueRailLayout.settle(reducesMotion: true) == Theme.Gesture.snapBack)
}

@Test func underReduceMotionALiftLandsOnTheDetentNearestTheFingerWithNoThrow() {
    let landing = reps.landing(liftedAt: reps.offset(centering: 4) - 30, velocity: -2000, reducesMotion: true)

    #expect(landing.index == 5)
    #expect(landing.spring == Theme.Gesture.snapBack)
    #expect(landing.initialVelocity == 0)
}

@Test func aDragClaimsTheRailWhenItIsAtLeastAsWideAsItIsTall() {
    #expect(ValueRailLayout.claimsAxis(CGSize(width: 10, height: 2)))
    #expect(ValueRailLayout.claimsAxis(CGSize(width: -8, height: 8)))
    #expect(!ValueRailLayout.claimsAxis(CGSize(width: 3, height: -12)))
}
