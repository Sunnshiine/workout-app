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
    let ground = [day.paper.baseTop, day.paper.baseBottom.opacity(0.35)]
    #expect(contrast(of: day.supersetPartnerName, over: ground) >= 4.5)
}

@Test func nightSupersetPartnerNameReadsAsText() throws {
    let night = Theme.palette(for: Theme.Appearance.night)
    let sunWash = try #require(night.paper.washes.first)
    #expect(contrast(of: night.supersetPartnerName, over: [night.paper.baseTop, sunWash.color]) >= 4.5)
}

@Test func daySecondaryTextReadsAsTextInTheStageFoot() throws {
    let day = Theme.palette(for: Theme.Appearance.day)
    let footWash = try #require(day.paper.washes.last)
    #expect(contrast(of: day.textSecondary, over: [day.paper.baseBottom, footWash.color]) >= 4.5)
}
