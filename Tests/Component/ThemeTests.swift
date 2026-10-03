import SwiftUI
import Testing

@testable import WorkoutTracker

#if canImport(AppKit)
    import AppKit
#endif

#if canImport(AppKit)
    private struct RGBAComponents {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    private func rgbaComponents(of color: Color) -> RGBAComponents? {
        NSColor(color).usingColorSpace(.deviceRGB).map {
            RGBAComponents(
                red: Double($0.redComponent),
                green: Double($0.greenComponent),
                blue: Double($0.blueComponent),
                alpha: Double($0.alphaComponent)
            )
        }
    }

    /// Asserts a color is sage-led rather than neutral black or a foreign hue — the pigment
    /// heart of the Room Re-lights Rule (DESIGN.md §2). Green must lead red and blue, and the
    /// channel spread must clear a floor so a re-lit surface can never collapse to gray/black.
    private func expectSageLed(
        _ color: Color,
        floor: Double = 0.012,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let rgb = rgbaComponents(of: color) else {
            Issue.record("Could not resolve color to deviceRGB", sourceLocation: sourceLocation)
            return
        }
        #expect(rgb.green >= rgb.red, "sage-led: green (\(rgb.green)) should lead red (\(rgb.red))", sourceLocation: sourceLocation)
        #expect(rgb.green > rgb.blue, "sage-led: green (\(rgb.green)) should lead blue (\(rgb.blue))", sourceLocation: sourceLocation)
        #expect(
            rgb.green - min(rgb.red, rgb.blue) >= floor,
            "not neutral: a channel spread ≥ \(floor) proves a preserved sage hue, not gray/black",
            sourceLocation: sourceLocation
        )
    }
#endif

// MARK: - Appearances

@Test func themeDayAppearanceIsLightNightIsDark() {
    #expect(Theme.palette(for: Theme.Appearance.day).preferredColorScheme == .light)
    #expect(Theme.palette(for: Theme.Appearance.night).preferredColorScheme == .dark)
    #expect(Theme.palette(for: Theme.Appearance.day).appearance == .day)
    #expect(Theme.palette(for: Theme.Appearance.night).appearance == .night)
}

// MARK: - Appearance resolution (preference × system scheme)

@Test func themeResolvesLightPreferenceToDayAndNightPreferenceToNight() {
    #expect(Theme.palette(for: AppearancePreference.light).appearance == .day)
    #expect(Theme.palette(for: AppearancePreference.night).appearance == .night)
}

@Test func themeSystemPreferenceFollowsColorSchemeAndSystemDarkMapsToNight() {
    #expect(Theme.palette(for: AppearancePreference.system, colorScheme: .light).appearance == .day)
    #expect(Theme.palette(for: AppearancePreference.system, colorScheme: .dark).appearance == .night)
}

@Test func themeForcedPreferencesIgnoreCurrentColorScheme() {
    #expect(Theme.palette(for: AppearancePreference.light, colorScheme: .dark).appearance == .day)
    #expect(Theme.palette(for: AppearancePreference.night, colorScheme: .light).appearance == .night)
}

@Test func themeColorSchemeOverrideOnlyForForcedPreferences() {
    #expect(Theme.colorSchemeOverride(for: AppearancePreference.system) == nil)
    #expect(Theme.colorSchemeOverride(for: AppearancePreference.light) == .light)
    #expect(Theme.colorSchemeOverride(for: AppearancePreference.night) == .dark)
}

// MARK: - Semantic roles (token sheet §3)

#if canImport(AppKit)
    @Test func themeDangerStaysADistinctDestructiveRed() {
        for appearance in Theme.Appearance.allCases {
            guard let danger = rgbaComponents(of: Theme.palette(for: appearance).danger) else {
                Issue.record("Could not resolve \(appearance) danger")
                return
            }
            #expect(danger.red > 0.85, "\(appearance) danger should read as red")
            #expect(danger.green < 0.35, "\(appearance) danger should not drift orange or green")
            #expect(danger.blue < 0.25, "\(appearance) danger should not drift purple")
        }
    }
#endif

// MARK: - Night validation of the two flagged surfaces (PRD #458 slice 8, ADR-0007)
//
// The Exercise History sheet and the Block grid were the two surfaces never re-prototyped at
// night; the map required them validated against the Room Re-lights Rule before their baselines
// lock (DESIGN.md §2: "Night is the same room re-lit, never recolored: hue-preserved deep sage
// paper, foliage pigment for everything that grows, cream kept as the light source. No neutral
// black, no new hues at night."). These assertions are the programmatic half of that sign-off —
// the deterministic Visual Baselines are the pixel half.

#if canImport(AppKit)
    @Test func nightExerciseHistorySheetObeysTheRoomRelightsRule() {
        let night = Theme.palette(for: Theme.Appearance.night)

        // The night sheet paper is deep sage, never neutral black (#418 recipe, flagged surface).
        expectSageLed(night.sheetFill)
        if let sheet = rgbaComponents(of: night.sheetFill) {
            #expect(sheet.green < 0.2, "the night sheet stays a deep sage paper, not a mid-tone")
        }

        // Cream stays the light source: carved chips and the grabber are cream at low opacity.
        for creamSurface in [night.chipCarvedFill, night.grabber] {
            expectSageLed(creamSurface)
            if let cream = rgbaComponents(of: creamSurface) {
                #expect(cream.green > 0.85, "cream is kept as the light source, sage-led and bright")
            }
        }
    }
#endif

#if canImport(AppKit)
    @Test func nightBlockGridObeysTheRoomRelightsRule() {
        let night = Theme.palette(for: Theme.Appearance.night)

        expectSageLed(night.sessionTileComplete)
        if let foliage = rgbaComponents(of: night.sessionTileComplete) {
            #expect(foliage.green > 0.4 && foliage.green < 0.75, "the complete tile is mid foliage, not ink or cream")
        }

        expectSageLed(night.tileGhostStroke)
        for creamSurface in [night.tileCurrentFill, night.weekCardShade] {
            expectSageLed(creamSurface)
            if let cream = rgbaComponents(of: creamSurface) {
                #expect(cream.green > 0.85, "cream is kept as the light source, sage-led and bright")
            }
        }
    }
#endif

#if canImport(AppKit)
    @Test func nightPreservesTheRoomsSageHueAcrossAppearances() {
        // The room re-lights, it does not recolor: the sheet paper and the page paper stay sage-led in
        // both appearances, only their lightness changes.
        for appearance in Theme.Appearance.allCases {
            let palette = Theme.palette(for: appearance)
            expectSageLed(palette.sheetFill)
            expectSageLed(palette.paper.baseTop)
            expectSageLed(palette.paper.baseBottom)
        }
    }
#endif
