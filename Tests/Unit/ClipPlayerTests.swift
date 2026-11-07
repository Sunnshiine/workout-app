import CoreGraphics
import Foundation
import Testing

@testable import WorkoutTracker

private func movie(frames: Int = 90) async throws -> URL {
    let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
    try await SyntheticMovie.write(to: url, frames: frames) { _ in SyntheticMovie.Point(x: 0.5, y: 0.5) }
    return url
}

private func still() throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil,
            width: 9,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    return try #require(context.makeImage())
}

/// A movie plays in real time, so this outlasts `waitUntil`'s bound. It waits for what playback
/// reports, since one read of a playing movie can land anywhere if the host stalls.
@MainActor
private func reportsTime(in moments: ClosedRange<Double>, on player: ClipPlayer) async -> Bool {
    for _ in 0..<50_000_000 {
        if moments.contains(player.time) { return true }
        await Task.yield()
    }
    return false
}

@Suite struct ClipPlaybackRateTests {
    @Test func eachSpeedPrintsItsMultipleAndSaysItsName() {
        #expect(ClipPlaybackRate.allCases.map(\.label) == ["0.25×", "0.5×", "1×"])
        #expect(ClipPlaybackRate.allCases.map(\.accessibilityLabel) == ["Quarter speed", "Half speed", "Full speed"])
    }
}

@MainActor
@Suite struct ClipPlayerTests {
    @Test func aMovieComesReadyAndReadsItsShape() async throws {
        let url = try await movie()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = ClipPlayer(url: url, duration: 3)
        defer { player.tearDown() }

        await player.loaded()

        #expect(player.isReady)
        #expect(player.aspect != nil)
        #expect(!player.isUnplayable)
    }

    @Test func aDamagedFileSaysSoRatherThanNeverOpening() async throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let player = ClipPlayer(url: url, duration: 3)
        defer { player.tearDown() }

        await player.loaded()

        #expect(player.isUnplayable)
        #expect(!player.isReady)
    }

    @Test func aSeekBeforeTheMovieIsReadyLandsOnceItIs() async throws {
        let url = try await movie()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = ClipPlayer(url: url, duration: 3)
        defer { player.tearDown() }

        player.seek(to: 1.5)
        #expect(player.time == 1.5)

        await player.loaded()
        await player.settled()
        #expect(abs(player.player.currentTime().seconds - 1.5) < 0.05)
    }

    /// A cover handing over from the picker shows the review, takes it away while the movie is still
    /// opening, and shows it again on the same player.
    @Test func aPlayerBackOnScreenAfterATearDownSeeksAndReportsAgain() async throws {
        let url = try await movie()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = ClipPlayer(url: url, duration: 3)
        defer { player.tearDown() }
        player.tearDown()

        player.setUp()
        await player.loaded()

        #expect(player.isReady)
        player.seek(to: 1.5)
        await player.settled()
        #expect(abs(player.player.currentTime().seconds - 1.5) < 0.05)
        player.play()
        #expect(await reportsTime(in: 1.51...3, on: player))
    }

    /// From 2.5 s, only a clip that reached its end, went back, and played on can report these.
    @Test func aLoopGoesBackToTheStartAtTheEnd() async throws {
        let url = try await movie()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = ClipPlayer(url: url, duration: 3)
        defer { player.tearDown() }
        await player.loaded()
        player.seek(to: 2.5)
        await player.settled()

        player.play()

        #expect(await reportsTime(in: 0.1...2.4, on: player))
        #expect(player.isPlaying)
    }

    @Test func aPressAtTheEndStartsTheClipOver() async throws {
        let url = try await movie()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = ClipPlayer(url: url, duration: 3)
        defer { player.tearDown() }
        await player.loaded()
        player.seek(to: 3)
        await player.settled()
        #expect(player.player.currentTime().seconds > 2.9)

        player.play()

        #expect(player.time == 0)
        #expect(player.isPlaying)
        #expect(await reportsTime(in: 0.1...2.9, on: player))
    }

    @Test func withLoopOffTheEndStopsThePlayer() async throws {
        let player = ClipPlayer(still: try still(), time: 3, duration: 3, rate: .full, isPlaying: true)
        player.loops = false

        player.reachedEnd()

        #expect(!player.isPlaying)
    }

    @Test func slowPlayMutesAndFullSpeedSoundsAgain() async throws {
        let url = try await movie()
        defer { try? FileManager.default.removeItem(at: url) }
        let player = ClipPlayer(url: url, duration: 3)
        defer { player.tearDown() }
        await player.loaded()
        player.play()

        player.setRate(.quarter)
        #expect(player.player.isMuted)
        #expect(player.player.rate == 0.25)

        player.setRate(.full)
        #expect(!player.player.isMuted)
    }

    @Test func aScrubLeavesTheClipPausedWhereTheFingerLeftIt() async throws {
        let player = ClipPlayer(still: try still(), time: 0, duration: 3, rate: .full, isPlaying: true)

        player.beginScrub()
        player.scrub(to: 9)
        player.endScrub()

        #expect(player.time == 3)
        #expect(!player.isPlaying)
    }
}

@MainActor
@Suite struct ClipComparisonTests {
    private func comparison(leftStart: Double, rightStart: Double) throws -> ClipComparison {
        ClipComparison(
            left: ClipPlayer(still: try still(), time: 0, duration: 9, rate: .full, isPlaying: false),
            right: ClipPlayer(still: try still(), time: 0, duration: 10.5, rate: .full, isPlaying: false),
            leftStart: leftStart,
            rightStart: rightStart
        )
    }

    @Test func bothOpenLinedUpAtTheirStarts() throws {
        let both = try comparison(leftStart: 1, rightStart: 2.5)

        #expect(both.left.time == 1)
        #expect(both.right.time == 2.5)
        #expect(both.sharedTime == 0)
    }

    @Test func aSharedScrubMovesBothTheSameDistance() throws {
        let both = try comparison(leftStart: 1, rightStart: 2.5)

        both.scrub(to: 2)

        #expect(both.left.time == 3)
        #expect(both.right.time == 4.5)
        #expect(both.sharedTime == 2)
    }

    @Test func aPaneMovesAloneUntilTheNextSharedPress() throws {
        let both = try comparison(leftStart: 0, rightStart: 0)
        both.scrub(.right, to: 2)
        #expect(both.left.time == 0)
        #expect(both.right.time == 2)

        both.togglePlaying()

        #expect(both.isPlaying)
        #expect(both.left.time == 0)
        #expect(both.right.time == 0)
    }

    @Test func markingAPaneLinesBothUpOnTheNewMark() throws {
        let both = try comparison(leftStart: 0, rightStart: 0)
        both.scrub(.right, to: 1.5)

        let mark = both.markStart(.right)

        #expect(mark == 1.5)
        #expect(both.left.time == 0)
        #expect(both.right.time == 1.5)
        #expect(both.timeline.right.start == 1.5)
        #expect(both.sharedTime == 0)
    }

    @Test func aLoopReturnsToTheStartOfTheSpanAndWithoutOneBothStop() throws {
        let both = try comparison(leftStart: 1, rightStart: 2.5)
        both.togglePlaying()
        both.scrub(to: 8)

        both.reachedEnd()
        #expect(both.isPlaying)
        #expect(both.sharedTime == both.timeline.span.lowerBound)

        both.loops = false
        both.reachedEnd()
        #expect(!both.isPlaying)
        #expect(!both.left.isPlaying)
        #expect(!both.right.isPlaying)
    }

    @Test func aTickPastWhereBothMoviesRunEndsThePlayThoughTheLongerGoesOn() throws {
        let both = try comparison(leftStart: 0, rightStart: 4)
        both.loops = false
        both.togglePlaying()
        let end = both.timeline.span.upperBound
        #expect(end == 6.5)

        both.left.seek(to: end - 0.5)
        both.left.onTick?(end - 0.5)
        #expect(both.isPlaying)

        both.left.seek(to: end)
        both.left.onTick?(end)
        #expect(!both.isPlaying)
        #expect(!both.right.isPlaying)
    }

    @Test func aRateChangeWhilePlayingReachesBoth() throws {
        let both = try comparison(leftStart: 0, rightStart: 0)
        both.togglePlaying()

        both.setRate(.quarter)

        #expect(both.left.rate == .quarter)
        #expect(both.right.rate == .quarter)
        #expect(both.isPlaying)
    }
}

@Suite struct FormClipPositionTests {
    @Test func aSetsOnlyClipNeedsNoCount() {
        let only = UUID()
        #expect(FormClipPosition(of: only, in: [only]) == nil)
    }

    @Test func theCountNamesThisClipAndWrapsToTheFirst() throws {
        let first = UUID()
        let second = UUID()

        let position = try #require(FormClipPosition(of: second, in: [first, second]))

        #expect(position.label == "2 of 2")
        #expect(position.next == first)
    }
}

@Suite struct ClipScrubDragTests {
    @Test func aDragMovesFromWhereTheFingerTookHoldAndStaysInRange() {
        #expect(ClipScrubDetent.time(grabbedAt: 3, moved: 100, across: 200, in: 0...8) == 7)
        #expect(ClipScrubDetent.time(grabbedAt: 3, moved: -400, across: 200, in: 0...8) == 0)
        #expect(ClipScrubDetent.time(grabbedAt: 3, moved: 900, across: 200, in: 0...8) == 8)
    }
}
