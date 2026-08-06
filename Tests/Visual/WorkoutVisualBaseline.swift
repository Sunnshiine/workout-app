import SnapshotTesting
import SwiftUI
import UIKit

enum WorkoutVisualBaseline {
    static let localeIdentifier = "en_US"
    static let dynamicTypeSize: DynamicTypeSize = .large
    static let precision: Float = 1.0
    static let labelAntialiasingPrecision: Float = 0.999
}

extension ViewImageConfig {
    @MainActor
    static var workoutVisualBaseline: ViewImageConfig {
        baseline(userInterfaceStyle: .light)
    }

    /// The Night edition of the baseline device: the same room re-lit under a `.dark` trait. The
    /// Greenhouse compositions carry explicit palette tokens and so re-light under the light config,
    /// but native surfaces (Settings, DESIGN.md §5.9) draw their system chrome from the trait — they
    /// need the trait itself flipped to render dark.
    @MainActor
    static var workoutVisualBaselineNight: ViewImageConfig {
        baseline(userInterfaceStyle: .dark)
    }

    @MainActor
    private static func baseline(userInterfaceStyle: UIUserInterfaceStyle) -> ViewImageConfig {
        ViewImageConfig(
            safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
            size: CGSize(width: 402, height: 874),
            traits: UITraitCollection { traits in
                traits.displayScale = 3
                traits.userInterfaceStyle = userInterfaceStyle
                traits.preferredContentSizeCategory = .large
                traits.layoutDirection = .leftToRight
            }
        )
    }
}
