import CoreGraphics
import Foundation
import Testing

@testable import WorkoutTracker

private let tolerance = 1e-6

@Suite struct MoveOnCeremonyFrameTests {
    @Test func theStemDrawsOnTheWingOverItsFirstSecondThenHolds() {
        #expect(MoveOnCeremonyFrame(elapsed: 0).stemTrim == 0)
        #expect(MoveOnCeremonyFrame(elapsed: 0.1).stemTrim == 0)
        #expect(abs(MoveOnCeremonyFrame(elapsed: 0.5).stemTrim - 0.115986) < tolerance)
        #expect(abs(MoveOnCeremonyFrame(elapsed: 0.75).stemTrim - 0.390863) < tolerance)
        #expect(MoveOnCeremonyFrame(elapsed: 1.0).stemTrim == 1)
        #expect(MoveOnCeremonyFrame(elapsed: 1.1).stemTrim == 1)
        #expect(MoveOnCeremonyFrame(elapsed: 1.45).stemTrim == 1)
    }

    @Test func theBirdWaitsOutTheBeatThenLandsOnTheWing() {
        #expect(MoveOnCeremonyFrame(elapsed: 0).birdLanding == 0)
        #expect(MoveOnCeremonyFrame(elapsed: 0.5).birdLanding == 0)
        #expect(MoveOnCeremonyFrame(elapsed: 1.0).birdLanding == 0)
        #expect(MoveOnCeremonyFrame(elapsed: 1.1).birdLanding == 0)
        #expect(MoveOnCeremonyFrame(elapsed: 1.135).birdLanding == 0)
        #expect(abs(MoveOnCeremonyFrame(elapsed: 1.275).birdLanding - 0.115986) < tolerance)
        #expect(abs(MoveOnCeremonyFrame(elapsed: 1.45).birdLanding - 1) < tolerance)
    }

    @Test func theGrownFrameHasTheWholeStemAndTheBirdLanded() {
        let grown = MoveOnCeremonyFrame(elapsed: MoveOnCeremonyFrame.duration)

        #expect(grown.stemTrim == 1)
        #expect(grown.birdLanding == 1)
        #expect(grown.leafInk(atLengthFraction: 0.91) == 1)
        #expect(MoveOnCeremonyFrame(elapsed: 5.0) == grown)
    }

    @Test func theGrownFrameInksALeafAtTheTipFully() {
        #expect(MoveOnCeremonyFrame(elapsed: MoveOnCeremonyFrame.duration).leafInk(atLengthFraction: 0.99) == 1)
    }

    @Test func aLeafInksAsTheTrimPassesItsPlaceOnTheStem() {
        let frame = MoveOnCeremonyFrame(elapsed: 0.75)

        #expect(frame.leafInk(atLengthFraction: 0.5) == 0)
        #expect(abs(frame.leafInk(atLengthFraction: 0.35) - 0.510793) < tolerance)
        #expect(frame.leafInk(atLengthFraction: 0.1) == 1)
    }

    @Test func aBezierFractionMeasuresPathLengthNotParameter() {
        let curve = QuadraticBezier(
            start: CGPoint(x: 10, y: 90),
            control: CGPoint(x: 55, y: 20),
            end: CGPoint(x: 100, y: 40)
        )

        #expect(curve.lengthFraction(at: 0) == 0)
        #expect(curve.lengthFraction(at: 1) == 1)
        #expect(abs(curve.lengthFraction(at: 0.5) - 0.584947) < 1e-4)
    }
}
