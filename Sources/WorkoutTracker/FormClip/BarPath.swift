import Foundation

/// The line a plate's center draws across a Form Clip, normalized to the displayed frame with its
/// origin at the top left. It is what happened and nothing more: no speed, depth, or verdict.
public struct BarPath: Codable, Equatable, Sendable {
    public struct Sample: Codable, Equatable, Sendable {
        public let time: Double
        public let x: Double
        public let y: Double

        public init(time: Double, x: Double, y: Double) {
            self.time = time
            self.x = x
            self.y = y
        }
    }

    public enum Ending: String, Codable, Sendable {
        /// The path follows the plate to the clip's last frame.
        case endOfClip
        /// The tracker lost the plate, so the path stops there rather than guess.
        case lostPlate
    }

    public let samples: [Sample]
    public let ending: Ending

    /// Smooths `tracked`. Nil when there is nothing to draw, because a path of one point is a tap.
    init?(tracked: [Sample], ending: Ending) {
        guard tracked.count > 1 else { return nil }
        samples = Self.smoothed(tracked)
        self.ending = ending
    }

    /// A centered triangular window, narrowing to nothing at each end, so the path lags no motion
    /// and still starts on the point the athlete tapped.
    static func smoothed(_ samples: [Sample]) -> [Sample] {
        samples.indices.map { index in
            let radius = min(Self.smoothingRadius, index, samples.count - 1 - index)
            var x = 0.0
            var y = 0.0
            var total = 0.0
            for offset in -radius...radius {
                let weight = Double(radius + 1 - abs(offset))
                x += samples[index + offset].x * weight
                y += samples[index + offset].y * weight
                total += weight
            }
            return Sample(time: samples[index].time, x: x / total, y: y / total)
        }
    }

    private static let smoothingRadius = 2

    /// The plate at `time`, between the two samples around it. Nil outside the path, so nothing
    /// marks a position the tracker never saw.
    public func position(at time: Double) -> Sample? {
        let next = firstIndex(after: time)
        guard next > 0 else { return nil }
        let before = samples[next - 1]
        guard next < samples.count else { return time == before.time ? before : nil }
        let after = samples[next]
        let share = (time - before.time) / (after.time - before.time)
        return Sample(time: time, x: before.x + (after.x - before.x) * share, y: before.y + (after.y - before.y) * share)
    }

    /// The part of the path the plate has already travelled by `time`.
    public func travelled(upTo time: Double) -> ArraySlice<Sample> {
        samples[..<firstIndex(after: time)]
    }

    /// The samples past `time`'s position start here, found by bisection so a frame's draw stays
    /// cheap on a long clip.
    private func firstIndex(after time: Double) -> Int {
        var low = 0
        var high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].time <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}

/// Where the athlete tapped the plate: a moment in the movie and a point on the displayed frame,
/// with its origin at the top left.
public struct BarPathStart: Equatable, Sendable {
    public let time: Double
    public let x: Double
    public let y: Double

    public init(time: Double, x: Double, y: Double) {
        self.time = time
        self.x = x
        self.y = y
    }
}

public protocol BarPathTracker: Sendable {
    /// Follows the plate forward from `start`, reporting the share of the clip it has read. It
    /// throws `CancellationError` as soon as its task is cancelled.
    func trace(_ movie: URL, from start: BarPathStart, progress: @escaping @Sendable (Double) -> Void) async throws -> BarPath
}
