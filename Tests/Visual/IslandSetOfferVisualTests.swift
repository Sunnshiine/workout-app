import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// The island's bottom region in Night, as production draws it, on the island's black.
@MainActor
@Suite(.snapshots(record: .never))
struct IslandSetOfferVisualTests {
    @Test func theLongestCellsGiveWayAtTheDefaultSize() {
        assertIslandBaseline(IslandOffer.longestCells.state, at: .large)
    }

    @Test func theLongestCellsGiveWayAtExtraExtraLarge() {
        assertIslandBaseline(IslandOffer.longestCells.state, at: .xxLarge)
    }

    @Test func theLongestCellsGiveWayAtTheLargestType() {
        assertIslandBaseline(IslandOffer.longestCells.state, at: .xxxLarge)
    }

    @Test func anOrdinarySetKeepsItsGuidanceAtTheDefaultSize() {
        assertIslandBaseline(IslandOffer.backSquat.state, at: .large)
    }

    private func assertIslandBaseline(
        _ state: WorkoutActivityAttributes.ContentState,
        at size: DynamicTypeSize,
        testName: String = #function
    ) {
        let view = IslandOffer.region(state, at: size).background(.black)
        let bounded = CGSize(width: IslandOffer.regionWidth, height: .greatestFiniteMagnitude)
        let height = UIHostingController(rootView: view).sizeThatFits(in: bounded).height
        assertSnapshot(
            of: view,
            as: .image(
                precision: WorkoutVisualBaseline.labelAntialiasingPrecision,
                layout: .fixed(width: IslandOffer.regionWidth, height: height),
                traits: UITraitCollection { traits in
                    traits.displayScale = 3
                    traits.userInterfaceStyle = .dark
                }
            ),
            testName: testName
        )
    }
}
