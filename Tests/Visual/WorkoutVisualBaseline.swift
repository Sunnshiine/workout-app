import SnapshotTesting
import SwiftUI
import UIKit

enum WorkoutVisualBaseline {
    static let localeIdentifier = "en_US"
    static let dynamicTypeSize: DynamicTypeSize = .large
    static let precision: Float = 1.0
}

extension ViewImageConfig {
    @MainActor
    static var workoutVisualBaseline: ViewImageConfig {
        ViewImageConfig(
            safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
            size: CGSize(width: 402, height: 874),
            traits: UITraitCollection { traits in
                traits.displayScale = 3
                traits.userInterfaceStyle = .light
                traits.preferredContentSizeCategory = .large
                traits.layoutDirection = .leftToRight
            }
        )
    }
}
