import SwiftUI
import Testing

@testable import WorkoutTracker

#if canImport(UIKit)
    import UIKit

    /// Proves the bundled variable faces actually load and that numeral roles render tabular, so a
    /// broken font bundle (missing `UIAppFonts` entry, mis-registered family, dropped resource)
    /// fails fast here rather than silently falling back to SF at runtime.
    ///
    /// UIKit-only: it exercises real registration + Core Text metrics, so it runs on the simulator,
    /// not the macOS `swift test` pass.

    @Test func bundledFontFamiliesAreRegistered() {
        let families = Set(UIFont.familyNames)
        #expect(families.contains("Fraunces"), "Fraunces did not register — check UIAppFonts / the bundled TTF")
        #expect(families.contains("Source Sans 3"), "Source Sans 3 did not register — check UIAppFonts / the bundled TTF")
    }

    @Test func frauncesVoiceResolvesToTheBundledFaceNotSF() {
        let font = Theme.uiFont(Theme.TypeRole.exerciseName.style)
        #expect(font.familyName == "Fraunces", "exerciseName fell back to \(font.familyName) instead of Fraunces")
    }

    @Test func sourceSansCarriesTheInstrumentNotSF() {
        let font = Theme.uiFont(Theme.TypeRole.weightEntry.style)
        #expect(font.familyName == "Source Sans 3", "weightEntry fell back to \(font.familyName) instead of Source Sans 3")
    }

    @Test func numeralRolesRenderTabular() {
        let font = Theme.uiFont(Theme.TypeRole.weightEntry.style)
        let widths = "0123456789".map { digit in
            (String(digit) as NSString).size(withAttributes: [.font: font]).width
        }
        let spread = (widths.max() ?? 0) - (widths.min() ?? 0)
        #expect(spread < 0.5, "weightEntry digits are not tabular — tnum plumbing is inactive (spread \(spread))")
    }

    @Test func nonTabularRolesLeaveDigitsProportional() {
        // Guards the tnum check above from a false positive: Source Sans 3's default figures are
        // proportional, so a role that does not request tnum must keep varying digit widths.
        let font = Theme.uiFont(Theme.TypeRole.railChipGlyph.style)
        let widths = "0123456789".map { digit in
            (String(digit) as NSString).size(withAttributes: [.font: font]).width
        }
        let spread = (widths.max() ?? 0) - (widths.min() ?? 0)
        #expect(spread > 0.01, "railChipGlyph unexpectedly rendered tabular — the tnum test can't distinguish plumbing")
    }
#endif
