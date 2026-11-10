import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct LockScreenRestFillVisualTests {
    private static let size = CGSize(width: 374, height: 160)
    private static let tooLongForTheClockToMoveTheEdge: TimeInterval = 1e12
    private static let longAgo = Date(timeIntervalSinceReferenceDate: -tooLongForTheClockToMoveTheEdge)
    private static let farAhead = Date(timeIntervalSinceReferenceDate: tooLongForTheClockToMoveTheEdge)

    @Test func aRestHalfRunFillsTheLeftHalfOfTheCardDay() {
        assertFillBaseline(.light, fill: .draining(over: Self.longAgo...Self.farAhead))
    }

    @Test func aRestHalfRunFillsTheLeftHalfOfTheCardNight() {
        assertFillBaseline(.dark, fill: .draining(over: Self.longAgo...Self.farAhead))
    }

    @Test func noRestLeavesTheCardEmptyNight() {
        assertFillBaseline(.dark, fill: nil)
    }

    private func assertFillBaseline(
        _ appearance: LiveActivityAppearance,
        fill: LockScreenFill?,
        testName: String = #function
    ) {
        let view = LockScreenCardBackground(leaf: .colors(for: appearance), fill: fill)
            .frame(width: Self.size.width, height: Self.size.height)

        assertSnapshot(
            of: view,
            as: .image(
                layout: .fixed(width: Self.size.width, height: Self.size.height),
                traits: UITraitCollection { traits in
                    traits.displayScale = 3
                    traits.userInterfaceStyle = appearance == .dark ? .dark : .light
                }
            ),
            testName: testName
        )
    }
}
