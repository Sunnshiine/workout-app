import AVFoundation
import Foundation
import Synchronization
import Vision

public enum BarPathTraceError: Error, Equatable, Sendable {
    case noVideoTrack
    case unreadableMovie
    /// The plate was lost before a second frame, which leaves no line to draw.
    case nothingFollowed
}

/// How a movie's frames sit in its display: what Vision needs to read them upright, and the shape
/// the athlete sees.
struct MovieDisplay: Equatable, Sendable {
    let orientation: CGImagePropertyOrientation
    /// Width over height, as displayed.
    let aspect: Double

    init(naturalSize: CGSize, transform: CGAffineTransform) {
        orientation = Self.orientation(of: transform)
        switch orientation {
        case .right, .left: aspect = naturalSize.height / naturalSize.width
        default: aspect = naturalSize.width / naturalSize.height
        }
    }

    private static func orientation(of transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }
}

/// Follows a tapped plate with `VNTrackObjectRequest`, frame by frame. Vision's rectangles have
/// their origin at the bottom left, so this is the one place a point flips.
public struct VisionBarPathTracker: BarPathTracker {
    /// The plate's hub and inner rings, as a share of the frame's width. Measured on the synthetic
    /// clip: the spike at this size holds a median error of 0.004 of the frame's width.
    static let seedWidth = 0.14
    /// Vision's own sign that it has let go of the object.
    static let lostConfidence: VNConfidence = 0.3
    /// A 240 fps slow-motion clip reads no better than this, and takes eight times as long.
    static let shortestInterval = 1.0 / 30
    /// Reading a frame and tracking it block their thread, so they run here and leave Swift's
    /// cooperative threads free. Three traces at once used up a 3-core machine's whole pool.
    private static let frameQueue = DispatchQueue(label: "com.sunnypatel.WorkoutTracker.bar-path", qos: .userInitiated)

    public init() {}

    public func trace(_ movie: URL, from start: BarPathStart, progress: @escaping @Sendable (Double) -> Void) async throws -> BarPath {
        let asset = AVURLAsset(url: movie)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw BarPathTraceError.noVideoTrack }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let duration = try await asset.load(.duration).seconds
        let display = MovieDisplay(naturalSize: naturalSize, transform: transform)
        let frames = try Self.openFrames(of: track, in: asset, from: start.time, to: duration)
        defer { frames.reader.cancelReading() }
        let cancellation = TraceCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Self.frameQueue.async {
                    continuation.resume(
                        with: Result {
                            try Self.follow(frames.output, display: display, from: start, cancellation: cancellation) { time in
                                progress(time / max(time, duration))
                            }
                        }
                    )
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func openFrames(
        of track: AVAssetTrack,
        in asset: AVAsset,
        from start: Double,
        to end: Double
    ) throws -> MovieFrames {
        guard let reader = try? AVAssetReader(asset: asset) else { throw BarPathTraceError.unreadableMovie }
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw BarPathTraceError.unreadableMovie }
        return MovieFrames(reader: reader, output: output)
    }

    private static func follow(
        _ output: AVAssetReaderTrackOutput,
        display: MovieDisplay,
        from start: BarPathStart,
        cancellation: TraceCancellation,
        reached: (Double) -> Void
    ) throws -> BarPath {
        let height = seedWidth * display.aspect
        var last = VNDetectedObjectObservation(
            boundingBox: CGRect(x: start.x - seedWidth / 2, y: 1 - start.y - height / 2, width: seedWidth, height: height)
        )
        var tracked = [BarPath.Sample(time: start.time, x: start.x, y: start.y)]
        var ending = BarPath.Ending.endOfClip
        let handler = VNSequenceRequestHandler()

        while let sample = output.copyNextSampleBuffer() {
            try cancellation.check()
            let time = sample.presentationTimeStamp.seconds
            guard time - tracked[tracked.count - 1].time >= shortestInterval - 0.001, let pixels = sample.imageBuffer else { continue }
            guard let observed = plate(after: last, in: pixels, orientation: display.orientation, with: handler) else {
                ending = .lostPlate
                break
            }
            last = observed
            tracked.append(BarPath.Sample(time: time, x: Double(observed.boundingBox.midX), y: 1 - Double(observed.boundingBox.midY)))
            reached(time)
        }
        guard let path = BarPath(tracked: tracked, ending: ending) else { throw BarPathTraceError.nothingFollowed }
        return path
    }

    /// Nil once Vision has let go of the plate.
    private static func plate(
        after last: VNDetectedObjectObservation,
        in pixels: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        with handler: VNSequenceRequestHandler
    ) -> VNDetectedObjectObservation? {
        let request = VNTrackObjectRequest(detectedObjectObservation: last)
        request.trackingLevel = .accurate
        guard (try? handler.perform([request], on: pixels, orientation: orientation)) != nil,
            let observed = request.results?.first as? VNDetectedObjectObservation,
            observed.confidence >= lostConfidence
        else { return nil }
        return observed
    }
}

/// A reader and its output, opened on the task and read on the frame queue, never both at once.
private struct MovieFrames: @unchecked Sendable {
    let reader: AVAssetReader
    let output: AVAssetReaderTrackOutput
}

/// A cancelled task's word to the frame loop, which runs off that task's thread.
private final class TraceCancellation: Sendable {
    private let isCancelled = Atomic(false)

    func cancel() {
        isCancelled.store(true, ordering: .relaxed)
    }

    func check() throws {
        if isCancelled.load(ordering: .relaxed) { throw CancellationError() }
    }
}
