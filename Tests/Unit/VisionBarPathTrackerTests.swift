import Foundation
import Synchronization
import Testing

@testable import WorkoutTracker

/// Tracks a generated movie for real, so a broken orientation or a flipped axis fails here. The
/// frames are small and few, so this stays fast under the flake guard's load.
@Suite struct VisionBarPathTrackerTests {
    private static let frames = 45

    /// Down then up, with the bar drifting forward at the bottom.
    private static func plate(_ frame: Int) -> SyntheticMovie.Point {
        let depth = (1 - cos(2 * Double.pi * Double(frame) / Double(frames))) / 2
        return SyntheticMovie.Point(x: 0.45 + 0.04 * depth, y: 0.3 + 0.3 * depth)
    }

    private func movie(
        transform: CGAffineTransform = .identity,
        plate: @Sendable (Int) -> SyntheticMovie.Point? = Self.plate
    ) async throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try await SyntheticMovie.write(to: url, frames: Self.frames, transform: transform, plate: plate)
        return url
    }

    private func worstError(of path: BarPath) -> Double {
        path.samples.map { sample in
            let truth = Self.plate(Int((sample.time * Double(SyntheticMovie.frameRate)).rounded()))
            return max(abs(sample.x - truth.x), abs(sample.y - truth.y) * 320 / 180)
        }.max() ?? .infinity
    }

    @Test(arguments: [
        CGAffineTransform.identity,
        CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 320, ty: 0),
        CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 180)
    ])
    func thePathFollowsThePlateInTheDisplayedFrame(transform: CGAffineTransform) async throws {
        let url = try await movie(transform: transform)
        defer { try? FileManager.default.removeItem(at: url) }
        let start = Self.plate(0)

        let path = try await VisionBarPathTracker().trace(url, from: BarPathStart(time: 0, x: start.x, y: start.y)) { _ in }

        #expect(path.ending == .endOfClip)
        #expect(path.samples.count >= Self.frames - 1)
        #expect(path.samples.first?.y == start.y)
        #expect(worstError(of: path) < 0.03, "worst error \(worstError(of: path)) of the frame's width")
    }

    @Test func thePathBeginsAtTheFrameTheAthleteTapped() async throws {
        let url = try await movie()
        defer { try? FileManager.default.removeItem(at: url) }
        let frame = 15
        let start = Self.plate(frame)
        let time = Double(frame) / Double(SyntheticMovie.frameRate)

        let path = try await VisionBarPathTracker().trace(url, from: BarPathStart(time: time, x: start.x, y: start.y)) { _ in }

        #expect(path.samples.first?.time == time)
        #expect(path.samples.count <= Self.frames - frame + 1)
        #expect(worstError(of: path) < 0.03)
    }

    @Test func aPlateThatLeavesTheFrameEndsThePathThereRatherThanGuessing() async throws {
        let gone = 20
        let url = try await movie { frame in frame < gone ? Self.plate(frame) : nil }
        defer { try? FileManager.default.removeItem(at: url) }
        let start = Self.plate(0)

        let path = try await VisionBarPathTracker().trace(url, from: BarPathStart(time: 0, x: start.x, y: start.y)) { _ in }

        #expect(path.ending == .lostPlate)
        let last = try #require(path.samples.last)
        #expect(last.time < Double(gone + 3) / Double(SyntheticMovie.frameRate))
    }

    @Test func aReportedShareRisesToTheEnd() async throws {
        let url = try await movie()
        defer { try? FileManager.default.removeItem(at: url) }
        let shares = RecordedShares()
        let start = Self.plate(0)

        _ = try await VisionBarPathTracker().trace(url, from: BarPathStart(time: 0, x: start.x, y: start.y)) { shares.append($0) }

        let reported = shares.values
        #expect(reported == reported.sorted())
        #expect((reported.last ?? 0) > 0.9)
    }

    @Test func aCancelledTraceStopsAndKeepsNothing() async throws {
        let url = try await movie()
        defer { try? FileManager.default.removeItem(at: url) }
        let start = Self.plate(0)
        let trace = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VisionBarPathTracker().trace(url, from: BarPathStart(time: 0, x: start.x, y: start.y)) { _ in }
        }

        await #expect(throws: CancellationError.self) { try await trace.value }
    }

    @Test func aFileWithNoVideoIsAnError() async throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) {
            try await VisionBarPathTracker().trace(url, from: BarPathStart(time: 0, x: 0.5, y: 0.5)) { _ in }
        }
    }
}

private final class RecordedShares: Sendable {
    private let held = Mutex<[Double]>([])

    func append(_ share: Double) {
        held.withLock { $0.append(share) }
    }

    var values: [Double] { held.withLock { $0 } }
}
