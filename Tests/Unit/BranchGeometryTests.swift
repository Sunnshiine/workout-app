import CoreGraphics
import Testing

@testable import WorkoutTracker

// MARK: - Quadratic bezier (the shared stem/branch geometry)

@Test func quadraticBezierAnchorsAtItsEndpoints() {
    let curve = QuadraticBezier(
        start: CGPoint(x: 10, y: 90),
        control: CGPoint(x: 55, y: 20),
        end: CGPoint(x: 100, y: 40)
    )

    #expect(curve.point(at: 0) == curve.start)
    #expect(curve.point(at: 1) == curve.end)
}

@Test func quadraticBezierPointMatchesTheClosedForm() {
    let curve = QuadraticBezier(
        start: CGPoint(x: 10, y: 90),
        control: CGPoint(x: 55, y: 20),
        end: CGPoint(x: 100, y: 40)
    )

    // An independent re-derivation of the formula the views used inline before the extraction,
    // proving the shared helper is byte-identical (the visual baselines depend on it).
    for t in stride(from: 0.0 as CGFloat, through: 1.0, by: 0.1) {
        let mt = 1 - t
        let expected = CGPoint(
            x: mt * mt * curve.start.x + 2 * mt * t * curve.control.x + t * t * curve.end.x,
            y: mt * mt * curve.start.y + 2 * mt * t * curve.control.y + t * t * curve.end.y
        )
        #expect(curve.point(at: t) == expected)
    }
}

@Test func quadraticBezierTangentMatchesTheClosedFormAndPointsFromStartToEnd() {
    let curve = QuadraticBezier(
        start: CGPoint(x: 10, y: 90),
        control: CGPoint(x: 55, y: 20),
        end: CGPoint(x: 100, y: 40)
    )

    for t in stride(from: 0.0 as CGFloat, through: 1.0, by: 0.25) {
        let mt = 1 - t
        let expected = CGVector(
            dx: 2 * mt * (curve.control.x - curve.start.x) + 2 * t * (curve.end.x - curve.control.x),
            dy: 2 * mt * (curve.control.y - curve.start.y) + 2 * t * (curve.end.y - curve.control.y)
        )
        #expect(curve.tangent(at: t) == expected)
    }

    // This stem climbs left→right, so every tangent advances in +x (leaves never point backwards).
    #expect(curve.tangent(at: 0).dx > 0)
    #expect(curve.tangent(at: 1).dx > 0)
}

// MARK: - Branch node layout (terminal-anchored spacing along the stem)

@Test func branchNodeLayoutSpreadsManyNodesAcrossTheFullSpan() {
    // Five nodes over 0.16…0.80: the natural step (0.16) is under the cap, so
    // the ends pin to the span — larger counts spread exactly as before.
    let ts = (0..<5).map {
        BranchNodeLayout.nodeT(index: $0, count: 5, first: 0.16, last: 0.80, maxStep: 0.24)
    }

    #expect(abs(ts[0] - 0.16) < 0.0001)
    #expect(abs(ts[4] - 0.80) < 0.0001)
}

@Test func branchNodeLayoutAnchorsTwoNodesToTheTerminal() {
    // Two Sets: the uncapped step would pin them to opposite ends of the branch
    // — too far apart to read as one sprig. The verdict anchors the last node
    // to the terminal and steps the other down by the capped step.
    let first = BranchNodeLayout.nodeT(index: 0, count: 2, first: 0.16, last: 0.80, maxStep: 0.24)
    let second = BranchNodeLayout.nodeT(index: 1, count: 2, first: 0.16, last: 0.80, maxStep: 0.24)

    #expect(abs(second - 0.80) < 0.0001)
    #expect(abs(first - 0.56) < 0.0001)
}

@Test func branchNodeLayoutThreeNodesStepDownFromTheTerminal() {
    let ts = (0..<3).map {
        BranchNodeLayout.nodeT(index: $0, count: 3, first: 0.16, last: 0.80, maxStep: 0.24)
    }

    #expect(abs(ts[2] - 0.80) < 0.0001)
    #expect(abs(ts[1] - 0.56) < 0.0001)
    #expect(abs(ts[0] - 0.32) < 0.0001)
}

@Test func branchNodeLayoutPutsASingleNodeAtTheTerminal() {
    let t = BranchNodeLayout.nodeT(index: 0, count: 1, first: 0.16, last: 0.80, maxStep: 0.24)

    #expect(abs(t - 0.80) < 0.0001)
}
