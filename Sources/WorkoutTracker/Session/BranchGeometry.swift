import CoreGraphics

/// A quadratic Bézier curve, sampled to place glyphs along the living stage's climbing stem, its
/// Superset lateral, and the ceremony branch (DESIGN.md §5.1 / §5.4 / §5.7). Pure geometry, lifted
/// out of the per-view sampling that was copied across those three sites so the arithmetic lives —
/// and is unit-tested — in one place rather than the Views.
struct QuadraticBezier: Equatable {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint

    /// The point at parameter `t` (0 = start, 1 = end).
    func point(at t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x,
            y: mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y
        )
    }

    /// The tangent (first derivative) vector at parameter `t`; take `atan2(dy, dx)` for its angle.
    func tangent(at t: CGFloat) -> CGVector {
        let mt = 1 - t
        return CGVector(
            dx: 2 * mt * (control.x - start.x) + 2 * t * (end.x - control.x),
            dy: 2 * mt * (control.y - start.y) + 2 * t * (end.y - control.y)
        )
    }
}

/// Places branch nodes along a stem's parameter space (the prototype verdict,
/// `docs/prototypes/branch-low-set-prototype.html`): the stem is always full
/// length, the last node anchors to the terminal at `last`, and earlier nodes
/// step down toward the root by `min(maxStep, (last − first) / (count − 1))` —
/// so 2–3 Sets read as a sprig growing at the stem's reach, and larger counts
/// spread down to `first` exactly as before.
enum BranchNodeLayout {
    static func nodeT(
        index: Int,
        count: Int,
        first: CGFloat,
        last: CGFloat,
        maxStep: CGFloat
    ) -> CGFloat {
        guard count > 1 else { return last }
        let step = min((last - first) / CGFloat(count - 1), maxStep)
        return last - step * CGFloat(count - 1 - index)
    }
}
