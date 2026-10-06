import SwiftUI
import Testing

@testable import WorkoutTracker

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

private func composite(_ layers: [Color], over ground: Color) -> SRGB {
    layers.reduce(srgbComponents(of: ground).rgb) { ground, layer in
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

private struct Ground {
    let base: Color
    let layers: [Color]
}

private func contrast(of mark: Color, over ground: Ground) -> Double {
    let lighter = relativeLuminance(composite(ground.layers + [mark], over: ground.base))
    let darker = relativeLuminance(composite(ground.layers, over: ground.base))
    return (max(lighter, darker) + 0.05) / (min(lighter, darker) + 0.05)
}

private func stepperPillGround(_ palette: Theme.Palette) -> Ground {
    Ground(base: palette.paper.baseTop, layers: [palette.surface, palette.pillFill])
}

/// The base gradient a third of the way down the page, below the partner name, with no wash.
private func dayUpperStageGround(_ day: Theme.Palette) -> Ground {
    Ground(base: day.paper.baseTop, layers: [day.paper.baseBottom.opacity(0.35)])
}

/// The top stop under the sun wash at full strength, the lightest ground light text meets up top.
private func nightSunlitGround(_ night: Theme.Palette) throws -> Ground {
    Ground(base: night.paper.baseTop, layers: [try #require(night.paper.washes.first).color])
}

/// The bottom stop under the foot wash at full strength, the darkest Day ground under text.
private func dayFootGround(_ day: Theme.Palette) throws -> Ground {
    Ground(base: day.paper.baseBottom, layers: [try #require(day.paper.washes.last).color])
}

@Test func paletteTokensResolveToTheirSRGBChannels() {
    let ink = srgbComponents(of: Theme.Paint.ink).rgb
    #expect(abs(ink.red - 21) <= 0.5 && abs(ink.green - 33) <= 0.5 && abs(ink.blue - 24) <= 0.5)
}

@Test func nightWeightStepperGlyphReadsAtThreeToOne() {
    let night = Theme.palette(for: Theme.Appearance.night)
    #expect(contrast(of: night.stepperGlyph, over: stepperPillGround(night)) >= 3.0)
}

@Test func dayWeightStepperGlyphReadsAtThreeToOne() {
    let day = Theme.palette(for: Theme.Appearance.day)
    #expect(contrast(of: day.stepperGlyph, over: stepperPillGround(day)) >= 3.0)
}

@Test func daySupersetPartnerNameReadsAsText() {
    let day = Theme.palette(for: Theme.Appearance.day)
    #expect(contrast(of: day.supersetPartnerName, over: dayUpperStageGround(day)) >= 4.5)
}

@Test func nightSupersetPartnerNameReadsAsText() throws {
    let night = Theme.palette(for: Theme.Appearance.night)
    #expect(contrast(of: night.supersetPartnerName, over: try nightSunlitGround(night)) >= 4.5)
}

@Test func daySecondaryTextReadsAsTextInTheStageFoot() throws {
    let day = Theme.palette(for: Theme.Appearance.day)
    #expect(contrast(of: day.textSecondary, over: try dayFootGround(day)) >= 4.5)
}
