import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import WorkoutTracker

private func setID(
    _ name: ExerciseName = "Back Squat",
    ordinal: Int = 0,
    block: String = "Block 27",
    week: Int = 1,
    day: Int = 1,
    index: Int = 0
) -> SetCoordinates.ID {
    SetCoordinates.ID(
        session: SessionCoordinate(blockTab: block, address: SessionAddress(week: week, day: day)),
        exercise: .unchecked(name: name, ordinal: ordinal),
        setIndex: index
    )
}

private func clip(
    on id: SetCoordinates.ID,
    logged: LoggedValue = .setLog(SetLog(weight: .pounds(185), reps: 5, rpe: .eight)),
    recordedAt: Date = Date(timeIntervalSince1970: 1_000)
) -> FormClip {
    FormClip(
        id: UUID(),
        spreadsheetId: "SHEET",
        setID: id,
        logged: logged,
        recordedAt: recordedAt,
        fileName: "movie.mov",
        byteCount: 1_000,
        duration: 9,
        barPath: nil,
        startMark: nil
    )
}

@Suite struct FormClipCaptionTests {
    @Test func aCaptionStatesTheNameSessionSetAndSetLog() {
        let log = SetLog(weight: .pounds(237.5), reps: 5, rpe: .six)
        let facts = FormClipFacts(setID: setID(index: 1), logged: .setLog(log))

        #expect(facts.caption == "Back Squat · W1 D1 · Set 2 · 237.5×5 @6")
    }

    @Test func aCadenceNeverReachesTheCoach() {
        let log = SetLog(weight: .pounds(135), reps: 8, rpe: .seven)
        let facts = FormClipFacts(setID: setID("2-3:1:0 BB RDL", index: 0), logged: .setLog(log))

        #expect(facts.caption == "BB RDL · W1 D1 · Set 1 · 135×8 @7")
    }

    @Test func aBodyweightSetLogReadsBW() {
        let log = SetLog(weight: .bodyweight, reps: 12, rpe: .seven)
        let facts = FormClipFacts(setID: setID("Pull Up", week: 3, day: 2, index: 2), logged: .setLog(log))

        #expect(facts.caption == "Pull Up · W3 D2 · Set 3 · BW×12 @7")
    }

    @Test func anUnstructuredSetLogReadsAsItsOwnText() {
        let facts = FormClipFacts(setID: setID(), logged: .unstructured("felt heavy, 185ish"))

        #expect(facts.caption == "Back Squat · W1 D1 · Set 1 · felt heavy, 185ish")
    }

    @Test func aSecondExerciseOfOneNameIsNumbered() {
        let log = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)
        let facts = FormClipFacts(setID: setID(ordinal: 1), logged: .setLog(log))

        #expect(facts.exerciseName == "Back Squat number 2")
    }
}

@Suite struct BarPathTests {
    private func path(_ points: [(Double, Double)]) throws -> BarPath {
        try #require(
            BarPath(
                tracked: points.enumerated().map { index, point in
                    BarPath.Sample(time: Double(index), x: point.0, y: point.1)
                },
                ending: .endOfClip
            )
        )
    }

    @Test func oneTrackedPointIsNoPath() {
        #expect(BarPath(tracked: [BarPath.Sample(time: 0, x: 0.5, y: 0.5)], ending: .lostPlate) == nil)
    }

    @Test func thePathStartsOnTheTappedPointAndEndsOnTheLastSeen() throws {
        let points = (0..<20).map { index in (0.4 + (index.isMultiple(of: 2) ? 0.01 : -0.01), 0.3 + Double(index) * 0.01) }

        let smoothed = try path(points)

        #expect(smoothed.samples.first == BarPath.Sample(time: 0, x: points[0].0, y: points[0].1))
        #expect(smoothed.samples.last == BarPath.Sample(time: 19, x: points[19].0, y: points[19].1))
        #expect(smoothed.samples.count == 20)
    }

    @Test func smoothingTakesOutJitterWithoutBendingAStraightLine() throws {
        let line = (0..<20).map { index in (0.4 + Double(index) * 0.002, 0.3 + Double(index) * 0.01) }
        let straight = try path(line)
        for (sample, truth) in zip(straight.samples, line) {
            #expect(abs(sample.x - truth.0) < 1e-9)
            #expect(abs(sample.y - truth.1) < 1e-9)
        }

        let jittered = line.enumerated().map { index, point in (point.0 + (index.isMultiple(of: 2) ? 0.006 : -0.006), point.1) }
        let smoothed = try path(jittered)
        let middle = 3..<17
        let before = middle.map { abs(jittered[$0].0 - line[$0].0) }.reduce(0, +)
        let after = middle.map { abs(smoothed.samples[$0].x - line[$0].0) }.reduce(0, +)
        #expect(after < before / 3)
    }

    @Test func aPositionFallsBetweenTheSamplesAroundIt() throws {
        let bar = try path([(0.2, 0.2), (0.2, 0.2), (0.2, 0.2), (0.4, 0.4), (0.4, 0.4), (0.4, 0.4)])

        let between = try #require(bar.position(at: 2.5))
        #expect(between.time == 2.5)
        #expect(between.x > 0.2 && between.x < 0.4)
        #expect(bar.position(at: 0)?.x == bar.samples[0].x)
        #expect(bar.position(at: 5)?.x == bar.samples[5].x)
    }

    @Test func nothingMarksAMomentTheTrackerNeverSaw() throws {
        let bar = try #require(
            BarPath(
                tracked: [BarPath.Sample(time: 1, x: 0.5, y: 0.5), BarPath.Sample(time: 2, x: 0.5, y: 0.6)],
                ending: .lostPlate
            )
        )

        #expect(bar.position(at: 0.5) == nil)
        #expect(bar.position(at: 2.5) == nil)
    }
}

@Suite struct CompareTimelineTests {
    private let timeline = CompareTimeline(
        left: .init(start: 2, duration: 10),
        right: .init(start: 5, duration: 9)
    )

    @Test func zeroIsBothLiftsStarting() {
        #expect(timeline.leftTime(at: 0) == 2)
        #expect(timeline.rightTime(at: 0) == 5)
    }

    @Test func bothPanesKeepTheirDistanceAsTimeRuns() {
        #expect(timeline.leftTime(at: 3) == 5)
        #expect(timeline.rightTime(at: 3) == 8)
    }

    @Test func theSpanRunsOnlyWhereBothMoviesHaveAFrame() {
        #expect(timeline.span == -2...4)
        #expect(timeline.rightTime(at: 100) == 9)
        #expect(timeline.leftTime(at: -100) == 0)
    }

    @Test func aMarkPastTheOtherMovieStillLeavesAValidSpan() {
        let tight = CompareTimeline(left: .init(start: 9, duration: 9), right: .init(start: 0, duration: 4))

        #expect(tight.span == 0...0)
        #expect(tight.leftTime(at: 3) == 9)
    }
}

@Suite struct BarPathStatusLineTests {
    private let lost = BarPath(
        tracked: [BarPath.Sample(time: 0, x: 0.5, y: 0.3), BarPath.Sample(time: 4.3, x: 0.5, y: 0.6)],
        ending: .lostPlate
    )

    @Test func aLostPlateSaysWhereThePathStopsWhileThePathIsShown() {
        let line = BarPathStatusLine.text(stage: .idle, path: lost, isShown: true, failure: nil)
        #expect(line == "The path stops at 0:04.3, where the plate was lost.")
        #expect(BarPathStatusLine.text(stage: .idle, path: lost, isShown: false, failure: nil) == nil)
    }

    @Test func followingCountsUpAndWaitingAsksForTheTap() {
        #expect(
            BarPathStatusLine.text(stage: .following(share: 0.42), path: nil, isShown: true, failure: nil) == "Following the plate. 42%"
        )
        #expect(
            BarPathStatusLine.text(stage: .awaitingTap, path: lost, isShown: true, failure: nil)
                == "Find where the Set starts, then tap the center of the plate."
        )
    }

    @Test func aDragClosesOnlyWhenItRunsDownwardAndFarEnough() {
        #expect(ClipCloseDrag.closes(width: 10, height: ClipCloseDrag.distance))
        #expect(!ClipCloseDrag.closes(width: 10, height: ClipCloseDrag.distance - 1))
        #expect(!ClipCloseDrag.closes(width: 200, height: 150))
        #expect(!ClipCloseDrag.closes(width: 0, height: -200))
    }

    @Test func aFailureSpeaksUntilTheNextAttempt() {
        let line = BarPathStatusLine.text(stage: .idle, path: nil, isShown: true, failure: BarPathTraceError.nothingFollowed.failureMessage)
        #expect(line == "The plate was lost right away. Try tapping its center on another frame.")
        #expect(BarPathStatusLine.text(stage: .idle, path: nil, isShown: true, failure: nil) == nil)
    }

    @Test func thePathTravelledGrowsWithTheClip() throws {
        let path = try #require(lost)
        #expect(path.travelled(upTo: -1).isEmpty)
        #expect(path.travelled(upTo: 1).count == 1)
        #expect(path.travelled(upTo: 5).count == path.samples.count)
    }
}

@Suite struct ClipTransportTests {
    @Test func aScrubTicksEachTimeItCrossesADetent() {
        #expect(ClipScrubDetent.crossed(from: 0.4, to: 0.6))
        #expect(ClipScrubDetent.crossed(from: 0.6, to: 0.4))
        #expect(!ClipScrubDetent.crossed(from: 0.1, to: 0.4))
        #expect(ClipScrubDetent.crossed(from: 3.2, to: 8.9))
    }

    @Test func aTimeReadsInMinutesSecondsAndTenths() {
        #expect(ClipTimeLabel.text(0) == "0:00.0")
        #expect(ClipTimeLabel.text(3.24) == "0:03.2")
        #expect(ClipTimeLabel.text(61.96) == "1:02.0")
        #expect(ClipTimeLabel.text(-1) == "0:00.0")
    }
}

@MainActor
@Suite struct FormClipPreviousTests {
    private func library(_ clips: [FormClip]) throws -> FormClipLibrary {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for clip in clips {
            try encoder.encode(clip).write(to: directory.appending(path: "\(clip.id.uuidString).json"))
            try Data().write(to: directory.appending(path: clip.fileName))
        }
        return FormClipLibrary(directory: directory, tracker: UnwiredBarPathTracker(), now: Date.init)
    }

    @Test func thePreviousClipIsTheNewestOfTheMovementFromAnotherSession() throws {
        let older = clip(on: setID(block: "Block 26", week: 4, day: 3), recordedAt: Date(timeIntervalSince1970: 100))
        let newer = clip(on: setID("0:2:0 Back Squat", day: 2), recordedAt: Date(timeIntervalSince1970: 200))
        let current = clip(on: setID(day: 3), recordedAt: Date(timeIntervalSince1970: 300))

        let found = try library([older, newer, current]).previous(of: current)

        #expect(found?.id == newer.id)
    }

    @Test func aDifferentMovementIsNeverOffered() throws {
        let bench = clip(on: setID("Bench Press", day: 2), recordedAt: Date(timeIntervalSince1970: 200))
        let paused = clip(on: setID("Paused Bench Press", day: 3), recordedAt: Date(timeIntervalSince1970: 300))

        #expect(try library([bench, paused]).previous(of: paused) == nil)
    }

    @Test func anotherSetOfTheSameSessionIsTheFallback() throws {
        let first = clip(on: setID(index: 0), recordedAt: Date(timeIntervalSince1970: 100))
        let second = clip(on: setID(index: 1), recordedAt: Date(timeIntervalSince1970: 200))

        #expect(try library([first, second]).previous(of: second)?.id == first.id)
    }

    @Test func aClipIsNeverItsOwnPrevious() throws {
        let only = clip(on: setID())

        #expect(try library([only]).previous(of: only) == nil)
    }

    @Test func aLaterSessionIsOfferedWhenNoEarlierOneHoldsAClip() throws {
        let later = clip(on: setID(day: 3), recordedAt: Date(timeIntervalSince1970: 500))
        let opened = clip(on: setID(day: 1), recordedAt: Date(timeIntervalSince1970: 100))

        #expect(try library([later, opened]).previous(of: opened)?.id == later.id)
    }
}

@Suite struct MovieDisplayTests {
    private let size = CGSize(width: 1920, height: 1080)

    @Test(arguments: [
        (CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0), CGImagePropertyOrientation.right),
        (CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920), .left)
    ])
    func aPortraitPhoneMovieTurnsItsPixelsAndItsShape(transform: CGAffineTransform, orientation: CGImagePropertyOrientation) {
        let display = MovieDisplay(naturalSize: size, transform: transform)

        #expect(display.orientation == orientation)
        #expect(display.aspect == 1080.0 / 1920.0)
    }

    @Test func anUpsideDownMovieKeepsItsShape() {
        let display = MovieDisplay(naturalSize: size, transform: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080))

        #expect(display.orientation == .down)
        #expect(display.aspect == 1920.0 / 1080.0)
    }

    @Test func anUntouchedMovieReadsAsStored() {
        #expect(MovieDisplay(naturalSize: size, transform: .identity).orientation == .up)
    }
}
