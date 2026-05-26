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

@Test func themeAccentIsAntiqueGold() {
    let accent = Theme.accent
    #if canImport(AppKit)
        guard let rgb = rgbComponents(of: accent) else {
            Issue.record("Could not resolve accent to deviceRGB")
            return
        }
        #expect(abs(rgb.red - 0.831) < 0.01, "Expected red ≈ 0.831, got \(rgb.red)")
        #expect(abs(rgb.green - 0.686) < 0.01, "Expected green ≈ 0.686, got \(rgb.green)")
        #expect(abs(rgb.blue - 0.216) < 0.01, "Expected blue ≈ 0.216, got \(rgb.blue)")
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

@Test func themeGradientIsNearBlackNeutral() {
    #if canImport(AppKit)
        for stop in Theme.gradientStops {
            guard let rgb = rgbComponents(of: stop.color) else { continue }
            #expect(rgb.red < 0.15, "Stop at \(stop.location): red \(rgb.red) too high for obsidian")
            #expect(rgb.green < 0.15, "Stop at \(stop.location): green \(rgb.green) too high for obsidian")
            #expect(rgb.blue < 0.15, "Stop at \(stop.location): blue \(rgb.blue) too high for obsidian")
        }
    #endif
}

@Test func themeCardCornerRadiusIs16() {
    #expect(Theme.cardCornerRadius == 16)
}

@Test func themeCardSpacingExists() {
    #expect(Theme.cardSpacing > 0)
}
