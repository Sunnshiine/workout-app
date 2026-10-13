import CoreGraphics

struct QuadraticBezier: Equatable {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint

    func point(at t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x,
            y: mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y
        )
    }

    func tangent(at t: CGFloat) -> CGVector {
        let mt = 1 - t
        return CGVector(
            dx: 2 * mt * (control.x - start.x) + 2 * t * (end.x - control.x),
            dy: 2 * mt * (control.y - start.y) + 2 * t * (end.y - control.y)
        )
    }
}

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
