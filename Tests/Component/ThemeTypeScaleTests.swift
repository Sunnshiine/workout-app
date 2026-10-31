import SwiftUI
import Testing

@testable import WorkoutTracker

#if canImport(UIKit)
    import UIKit

    @Test(arguments: Theme.TypeRole.allCases)
    func everyRoleKeepsItsDesignSizeAtTheDefaultContentSize(role: Theme.TypeRole) {
        #expect(Theme.scaledSize(role, at: .large) == role.style.size)
    }

    @Test(arguments: Theme.TypeRole.allCases)
    func everyRoleGrowsAtTheLargestAccessibilitySize(role: Theme.TypeRole) {
        #expect(Theme.scaledSize(role, at: .accessibility5) > role.style.size * 1.5)
    }

    @Test func aScaledRoleKeepsItsFaceAndTabularFigures() {
        let font = Theme.uiFont(
            Theme.TypeRole.weightEntry.style,
            size: Theme.scaledSize(.weightEntry, at: .accessibility5)
        )
        #expect(font.familyName == "Source Sans 3")
        #expect(font.pointSize > 46)
        let widths = "0123456789".map { ($0.description as NSString).size(withAttributes: [.font: font]).width }
        #expect((widths.max() ?? 0) - (widths.min() ?? 0) < 0.5)
    }
#endif
