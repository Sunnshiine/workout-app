import Foundation

/// Where following a plate stands in a review.
enum BarPathTraceStage: Equatable, Sendable {
    case idle
    /// The clip is paused, and the next tap on the frame is the plate's center.
    case awaitingTap
    case following(share: Double)
}

/// What a review says about the Bar Path, under the movie.
enum BarPathStatusLine {
    static func text(stage: BarPathTraceStage, path: BarPath?, isShown: Bool, failure: String?) -> String? {
        switch stage {
        case .awaitingTap:
            return "Find where the Set starts, then tap the center of the plate."
        case .following(let share):
            return "Following the plate. \(Int((share * 100).rounded()))%"
        case .idle:
            return failure ?? (isShown ? path?.lostPlateLine : nil)
        }
    }
}

extension BarPath {
    /// Where a lost plate stopped the path. Nil for a path that ran to the clip's end.
    fileprivate var lostPlateLine: String? {
        guard ending == .lostPlate, let last = samples.last else { return nil }
        return "The path stops at \(ClipTimeLabel.text(last.time)), where the plate was lost."
    }
}

extension BarPathTraceError {
    /// What the athlete reads when following the plate fails outright.
    var failureMessage: String {
        switch self {
        case .noVideoTrack, .unreadableMovie: "This movie can't be read frame by frame, so it can't be traced."
        case .nothingFollowed: "The plate was lost right away. Try tapping its center on another frame."
        case .trackingFailed: "The plate couldn't be followed this time. Try it again."
        }
    }
}
