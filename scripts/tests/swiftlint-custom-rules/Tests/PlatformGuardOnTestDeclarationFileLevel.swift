import SwiftUI
import Testing

@testable import WorkoutTracker

#if canImport(UIKit)
    import UIKit

    @Test func assertionInsideAFileLevelGuardPasses() {
        let families = Set(UIFont.familyNames)
        #expect(families.contains("Fraunces"))
    }

    @Test func bindingThenAssertionInsideAFileLevelGuardPasses() {
        let font = Theme.uiFont(Theme.TypeRole.weightEntry.style)
        #expect(font.familyName == "Source Sans 3")
    }
#endif
