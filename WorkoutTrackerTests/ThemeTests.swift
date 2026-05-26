import SwiftUI
import Testing

@testable import WorkoutTracker

#if canImport(AppKit)
    import AppKit
#endif

#if canImport(AppKit)
    private func rgbComponents(of color: Color) -> (r: Double, g: Double, b: Double)? {
        NSColor(color).usingColorSpace(.deviceRGB).map {
            (Double($0.redComponent), Double($0.greenComponent), Double($0.blueComponent))
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
        guard let (r, g, b) = rgbComponents(of: accent) else {
            Issue.record("Could not resolve accent to deviceRGB")
            return
        }
        #expect(abs(r - 0.831) < 0.01, "Expected red ≈ 0.831, got \(r)")
        #expect(abs(g - 0.686) < 0.01, "Expected green ≈ 0.686, got \(g)")
        #expect(abs(b - 0.216) < 0.01, "Expected blue ≈ 0.216, got \(b)")
    #endif
}

@Test func themeGradientHasNoOrangeTones() {
    #if canImport(AppKit)
        for stop in Theme.gradientStops {
            guard let (r, g, _) = rgbComponents(of: stop.color) else { continue }
            // Orange: high red AND red significantly dominates green
            #expect(
                !(r > 0.3 && r > 1.5 * g),
                "Stop at location \(stop.location) is orange: r=\(r) g=\(g)"
            )
        }
    #endif
}

@Test func themeGradientIsNearBlackNeutral() {
    #if canImport(AppKit)
        for stop in Theme.gradientStops {
            guard let (r, g, b) = rgbComponents(of: stop.color) else { continue }
            #expect(r < 0.15, "Stop at \(stop.location): red \(r) too high for obsidian")
            #expect(g < 0.15, "Stop at \(stop.location): green \(g) too high for obsidian")
            #expect(b < 0.15, "Stop at \(stop.location): blue \(b) too high for obsidian")
        }
    #endif
}

@Test func themeCardCornerRadiusIs16() {
    #expect(Theme.cardCornerRadius == 16)
}

@Test func themeCardSpacingExists() {
    #expect(Theme.cardSpacing > 0)
}
