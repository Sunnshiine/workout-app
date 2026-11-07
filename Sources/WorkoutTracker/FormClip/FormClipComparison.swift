import Foundation

extension FormClipLibrary {
    /// What a Compare opens beside `clip`: the newest earlier clip of its Movement from another
    /// Session, or failing that, any other clip of its Movement. Movement is matched here, at query
    /// time, against the clip's own name (ADR-0013).
    func previous(of clip: FormClip) -> FormClip? {
        let others = comparable(with: clip)
        return others.first { $0.setID.session != clip.setID.session && $0.recordedAt <= clip.recordedAt }
            ?? others.first { $0.setID.session != clip.setID.session }
            ?? others.first
    }

    /// Every other clip of `clip`'s Movement, newest first.
    func comparable(with clip: FormClip) -> [FormClip] {
        clips.filter { $0.id != clip.id && clip.setID.exercise.name.isSameMovement(as: $0.setID.exercise.name) }
    }
}

/// Two Form Clips playing as one, lined up at their Start Marks. Shared time is seconds past the
/// marks: zero is both Sets starting, and it runs only as far as both movies do.
struct CompareTimeline: Equatable, Sendable {
    struct Pane: Equatable, Sendable {
        let start: Double
        let duration: Double
    }

    let left: Pane
    let right: Pane

    init(left: Pane, right: Pane) {
        self.left = left
        self.right = right
    }

    var span: ClosedRange<Double> {
        let before = min(left.start, right.start)
        let after = min(left.duration - left.start, right.duration - right.start)
        return -before...max(-before, after)
    }

    func leftTime(at shared: Double) -> Double { left.start + clamped(shared) }

    func rightTime(at shared: Double) -> Double { right.start + clamped(shared) }

    func clamped(_ shared: Double) -> Double {
        min(max(shared, span.lowerBound), span.upperBound)
    }
}

/// The speeds a review plays at.
enum ClipPlaybackRate: Double, CaseIterable, Sendable {
    case quarter = 0.25
    case half = 0.5
    case full = 1

    var label: String {
        switch self {
        case .quarter: "0.25×"
        case .half: "0.5×"
        case .full: "1×"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .quarter: "Quarter speed"
        case .half: "Half speed"
        case .full: "Full speed"
        }
    }
}

/// Where a scrub ticks: often enough to feel the clip pass under the finger, and no more than once
/// a drag update however fast the finger goes.
enum ClipScrubDetent {
    /// Where a relative drag lands: the whole range across `width`, from where the finger took hold.
    static func time(grabbedAt: Double, moved: Double, across width: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        return min(max(grabbedAt + moved / max(width, 1) * span, range.lowerBound), range.upperBound)
    }

    static let interval = 0.5

    static func crossed(from old: Double, to new: Double) -> Bool {
        (old / interval).rounded(.down) != (new / interval).rounded(.down)
    }
}

/// When a drag on a movie means close: downward from its first move, and far enough once let go.
enum ClipCloseDrag {
    static let distance = 96.0

    static func isDownward(width: Double, height: Double) -> Bool {
        height > abs(width)
    }

    static func closes(width: Double, height: Double) -> Bool {
        height >= distance && isDownward(width: width, height: height)
    }
}

/// `0:03.2`, the way a review reads a moment in a clip.
enum ClipTimeLabel {
    static func text(_ seconds: Double) -> String {
        let tenths = Int((max(seconds, 0) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }
}

/// Where one clip sits among its Set's clips, when it has company.
struct FormClipPosition: Equatable {
    let label: String
    let next: UUID

    /// Nil for a Set's only clip, which needs no count.
    init?(of id: UUID, in ids: [UUID]) {
        guard ids.count > 1, let index = ids.firstIndex(of: id) else { return nil }
        label = "\(index + 1) of \(ids.count)"
        next = ids[(index + 1) % ids.count]
    }
}
