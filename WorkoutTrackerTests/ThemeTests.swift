import SwiftUI
import Testing

@testable import WorkoutTracker

#if canImport(AppKit)
    import AppKit
#endif

#if canImport(AppKit)
    private struct RGBComponents {
        let red: Double
        let green: Double
        let blue: Double
    }

    private func rgbComponents(of color: Color) -> RGBComponents? {
        NSColor(color).usingColorSpace(.deviceRGB).map {
            RGBComponents(
                red: Double($0.redComponent),
                green: Double($0.greenComponent),
                blue: Double($0.blueComponent)
            )
        }
    }
#endif

@Test func themeGradientHasTwoStops() {
    #expect(Theme.gradientStops.count == 2)
}

@Test func themeGradientTopIsAtZero() {
    #expect(Theme.gradientStops[0].location == 0)
}

@Test func themeGradientBottomIsAtOne() {
    #expect(Theme.gradientStops[1].location == 1)
}

@Test func themeAccentIsMintGreen() {
    let accent = Theme.accent
    #if canImport(AppKit)
        guard let rgb = rgbComponents(of: accent) else {
            Issue.record("Could not resolve accent to deviceRGB")
            return
        }
        #expect(abs(rgb.red - 0.45) < 0.01, "Expected red ≈ 0.45, got \(rgb.red)")
        #expect(abs(rgb.green - 1.0) < 0.01, "Expected green ≈ 1.0, got \(rgb.green)")
        #expect(abs(rgb.blue - 0.72) < 0.01, "Expected blue ≈ 0.72, got \(rgb.blue)")
    #endif
}

@Test func themeGradientHasNoOrangeTones() {
    #if canImport(AppKit)
        for stop in Theme.gradientStops {
            guard let rgb = rgbComponents(of: stop.color) else { continue }
            // Orange: high red AND red significantly dominates green
            #expect(
                !(rgb.red > 0.3 && rgb.red > 1.5 * rgb.green),
                "Stop at location \(stop.location) is orange: r=\(rgb.red) g=\(rgb.green)"
            )
        }
    #endif
}

@Test func themeGradientMovesToDarkBlackGreenDirection() {
    #if canImport(AppKit)
        for stop in Theme.gradientStops {
            guard let rgb = rgbComponents(of: stop.color) else { continue }
            #expect(rgb.red < 0.12, "Stop at \(stop.location): red \(rgb.red) too high for dark green")
            #expect(rgb.green < 0.18, "Stop at \(stop.location): green \(rgb.green) too high for dark green")
            #expect(rgb.blue < 0.12, "Stop at \(stop.location): blue \(rgb.blue) too high for dark green")
        }

        guard let bottom = rgbComponents(of: Theme.gradientStops[1].color) else {
            Issue.record("Could not resolve bottom gradient stop to deviceRGB")
            return
        }
        #expect(bottom.green > bottom.red + 0.03, "Expected bottom stop to lean green")
        #expect(bottom.green > bottom.blue + 0.02, "Expected bottom stop to lean green")
    #endif
}

@Test func themeSessionProgressTrackIsDarkBehindMintFill() {
    #if canImport(AppKit)
        guard let rgb = rgbComponents(of: Theme.progressTrack) else {
            Issue.record("Could not resolve progress track to deviceRGB")
            return
        }
        #expect(rgb.red < 0.08)
        #expect(rgb.green < 0.12)
        #expect(rgb.blue < 0.10)
        #expect(rgb.green >= rgb.red)
    #endif
}

@Test func themeActiveCardSurfaceUsesGreenFillAndStroke() {
    #if canImport(AppKit)
        guard let fill = rgbComponents(of: Theme.activeCardFill) else {
            Issue.record("Could not resolve active card fill to deviceRGB")
            return
        }
        guard let stroke = rgbComponents(of: Theme.activeCardStroke) else {
            Issue.record("Could not resolve active card stroke to deviceRGB")
            return
        }

        #expect(fill.green > fill.red + 0.10)
        #expect(fill.green > fill.blue + 0.05)
        #expect(stroke.green > stroke.red + 0.30)
        #expect(stroke.green > stroke.blue + 0.20)
    #endif
}

@Test func themeCardCornerRadiusIs16() {
    #expect(Theme.cardCornerRadius == 16)
}

@Test func themeCardSpacingExists() {
    #expect(Theme.cardSpacing > 0)
}

@Test func themeIncludesSmartValuePillAndRPEGridConstants() {
    #expect(Theme.pillMinHeight == 86)
    #expect(Theme.weightIncrementThreshold == 100)
    #expect(Theme.lightWeightIncrementOptions == [2.5, 5])
    #expect(Theme.heavyWeightIncrementOptions == [5, 10])
    #expect(Theme.rpeGridCellHeight == 48)
}
