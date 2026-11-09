import CoreGraphics

/// A rail's strip of cells and the finger on it (DESIGN.md §9). The strip's offset is its leading
/// edge's distance from the track's, so the cell under the track's centre is the one selected. A
/// drag moves the offset with the finger, rubber-bands past either end, and on release settles on
/// the detent nearest where the throw would have come to rest. The view only wires the gesture;
/// every number comes from here. The rails are offset-driven, never `scrollTo`, because an
/// offscreen snapshot render leaves a scroll view's content offset at 0.
struct ValueRailLayout: Equatable {
    let trackWidth: CGFloat
    let cellWidth: CGFloat
    let spacing: CGFloat
    let count: Int

    /// Where the strip rests once the finger lifts, and the spring that takes it there.
    struct Landing: Equatable {
        let index: Int
        let spring: Theme.SpringTuning
        /// The release velocity as a share of the distance left, which is the seed
        /// `interpolatingSpring(initialVelocity:)` takes.
        let initialVelocity: Double
    }

    /// Whether a drag that has travelled past the hysteresis is the rail's, or belongs to the
    /// surface beneath it.
    static func claimsAxis(_ translation: CGSize) -> Bool {
        abs(translation.width) >= abs(translation.height)
    }

    private var stride: CGFloat { cellWidth + spacing }

    /// The offset at which the first cell sits under the centre: the strip's rightmost rest.
    private var firstOffset: CGFloat { offset(centering: 0) }

    /// The offset at which the last cell sits under the centre: the strip's leftmost rest.
    private var lastOffset: CGFloat { offset(centering: max(count - 1, 0)) }

    /// The offset that puts `index`'s cell under the track's centre.
    func offset(centering index: Int) -> CGFloat {
        trackWidth / 2 - (stride * CGFloat(index) + cellWidth / 2)
    }

    /// The cell under the track's centre at `offset`, held to the strip's ends.
    func centredIndex(at offset: CGFloat) -> Int {
        guard stride > 0, count >= 1 else { return 0 }
        let index = Int(((trackWidth / 2 - offset - cellWidth / 2) / stride).rounded())
        return min(max(index, 0), count - 1)
    }

    /// Where a drag's travel is measured from: the strip's drawn offset, un-banded so a grab past
    /// an end carries on from the finger's true position, less the travel already spent reaching
    /// the hysteresis, so the strip does not jump when the drag is recognised.
    func dragAnchor(grabbedAt rendered: CGFloat, translation: CGFloat) -> CGFloat {
        unband(rendered) - translation
    }

    /// The strip's offset while the finger is down: the anchor plus the finger's travel, 1:1
    /// between the ends and rubber-banded past them.
    func draggedOffset(anchor: CGFloat, translation: CGFloat) -> CGFloat {
        band(anchor + translation)
    }

    /// The detent the strip settles on from `offset` with the finger moving at `velocity` points
    /// per second, and the spring that carries it there. A throw lands on the detent nearest its
    /// projected rest, seeded with the lift speed. A lift past an end, or one under Reduce Motion,
    /// lands on the detent nearest the finger on the snap-back spring with no projection and no
    /// seed: past the band the finger's speed is not the strip's, and a seed would throw it further out.
    func landing(liftedAt offset: CGFloat, velocity: CGFloat, reducesMotion: Bool) -> Landing {
        if reducesMotion {
            return Landing(index: centredIndex(at: offset), spring: Theme.Gesture.snapBack, initialVelocity: 0)
        }
        let rate = Theme.Gesture.railDecelerationRate
        let projected = offset + velocity / 1000 * rate / (1 - rate)
        let index = centredIndex(at: projected)
        let remaining = self.offset(centering: index) - offset
        if isPastAnEnd(offset) {
            return Landing(index: index, spring: Theme.Gesture.snapBack, initialVelocity: 0)
        }
        return Landing(
            index: index,
            spring: Theme.Gesture.release,
            initialVelocity: remaining == 0 ? 0 : velocity / remaining
        )
    }

    /// The spring that recentres the strip when a tap or a VoiceOver step moves the selection: the
    /// release spring, or under Reduce Motion the snap-back, whose 0.2 s is the longest settle §9 allows.
    static func settle(reducesMotion: Bool) -> Theme.SpringTuning {
        reducesMotion ? Theme.Gesture.snapBack : Theme.Gesture.release
    }

    private func isPastAnEnd(_ offset: CGFloat) -> Bool {
        offset > firstOffset || offset < lastOffset
    }

    /// Apple's rubber band: past an end the strip follows `(x · d · c) / (d + c · |x|)` of the
    /// finger's overshoot `x`, with `d` the track's width.
    private func band(_ raw: CGFloat) -> CGFloat {
        let constant = Theme.Gesture.rubberBandConstant
        func banded(_ overshoot: CGFloat) -> CGFloat {
            (overshoot * trackWidth * constant) / (trackWidth + constant * abs(overshoot))
        }
        if raw > firstOffset { return firstOffset + banded(raw - firstOffset) }
        if raw < lastOffset { return lastOffset + banded(raw - lastOffset) }
        return raw
    }

    /// The finger's overshoot that `band` drew at a given offset.
    private func unband(_ drawn: CGFloat) -> CGFloat {
        let constant = Theme.Gesture.rubberBandConstant
        func overshoot(_ banded: CGFloat) -> CGFloat {
            (banded * trackWidth) / (constant * (trackWidth - abs(banded)))
        }
        if drawn > firstOffset { return firstOffset + overshoot(drawn - firstOffset) }
        if drawn < lastOffset { return lastOffset + overshoot(drawn - lastOffset) }
        return drawn
    }
}
