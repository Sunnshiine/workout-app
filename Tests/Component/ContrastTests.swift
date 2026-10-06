import SwiftUI
import Testing

@testable import WorkoutTracker

// WCAG 2 contrast for the marks that sit nearest their floor, computed from the palette tokens so
// a token that regresses fails here: 3:1 for a control glyph, 4.5:1 for text. Each mark is
// composited over the ground it is drawn on. The weight ± glyph sits on the pill, over the Active
// Set Card surface, over the paper's top stop. The Superset partner name sits on the paper's top
// stop. Day secondary text in the stage foot sits on the paper's bottom stop under the last wash,
// the deep sage that pools at the foot; it is the darkest Day ground secondary text meets, so it
// is the worst case.

private struct SRGB {
    let red: Double
    let green: Double
    let blue: Double
}

private func srgbComponents(of color: Color) -> (rgb: SRGB, alpha: Double) {
    let resolved = color.resolve(in: EnvironmentValues())
    let rgb = SRGB(
        red: Double(resolved.red) * 255,
        green: Double(resolved.green) * 255,
        blue: Double(resolved.blue) * 255
    )
    return (rgb, Double(resolved.opacity))
}

/// Paints `layers` bottom to top with source-over in sRGB 0–255. The bottom layer is the opaque
/// ground, so its own alpha is ignored.
private func composite(_ layers: [Color]) -> SRGB {
    layers.dropFirst().reduce(srgbComponents(of: layers[0]).rgb) { ground, layer in
        let (top, alpha) = srgbComponents(of: layer)
        return SRGB(
            red: top.red * alpha + ground.red * (1 - alpha),
            green: top.green * alpha + ground.green * (1 - alpha),
            blue: top.blue * alpha + ground.blue * (1 - alpha)
        )
    }
}

private func relativeLuminance(_ color: SRGB) -> Double {
    func linear(_ channel: Double) -> Double {
        let value = channel / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
}

/// The contrast of `mark` drawn over `ground`, the layers under it listed bottom to top.
private func contrast(of mark: Color, over ground: [Color]) -> Double {
    let lighter = relativeLuminance(composite(ground + [mark]))
    let darker = relativeLuminance(composite(ground))
    return (max(lighter, darker) + 0.05) / (min(lighter, darker) + 0.05)
}

private func stepperGround(_ palette: Theme.Palette) -> [Color] {
    [palette.paper.baseTop, palette.surface, palette.pillFill]
}

@Test func paletteTokensResolveToTheirSRGBChannels() {
    let ink = srgbComponents(of: Theme.Paint.ink).rgb
    #expect(abs(ink.red - 21) <= 0.5 && abs(ink.green - 33) <= 0.5 && abs(ink.blue - 24) <= 0.5)
}

@Test func nightWeightStepperGlyphReadsAtThreeToOne() {
    let night = Theme.palette(for: Theme.Appearance.night)
    #expect(contrast(of: night.stepperGlyph, over: stepperGround(night)) >= 3.0)
}

@Test func dayWeightStepperGlyphReadsAtThreeToOne() {
    let day = Theme.palette(for: Theme.Appearance.day)
    #expect(contrast(of: day.stepperGlyph, over: stepperGround(day)) >= 3.0)
}

@Test func daySupersetPartnerNameReadsAsText() {
    let day = Theme.palette(for: Theme.Appearance.day)
    #expect(contrast(of: day.supersetPartnerName, over: [day.paper.baseTop]) >= 4.5)
}

@Test func nightSupersetPartnerNameReadsAsText() {
    let night = Theme.palette(for: Theme.Appearance.night)
    #expect(contrast(of: night.supersetPartnerName, over: [night.paper.baseTop]) >= 4.5)
}

@Test func daySecondaryTextReadsAsTextInTheStageFoot() throws {
    let day = Theme.palette(for: Theme.Appearance.day)
    let footWash = try #require(day.paper.washes.last)
    #expect(contrast(of: day.textSecondary, over: [day.paper.baseBottom, footWash.color]) >= 4.5)
}
