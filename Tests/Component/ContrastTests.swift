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

/// The living paper at `point` of its frame, as `paperBackground` draws it: the base gradient, then
/// each wash fading linearly from its centre to its radius.
private func paperGround(_ palette: Theme.Palette, at point: UnitPoint) -> Ground {
    let washes = palette.paper.washes.map { wash in
        let reach = 1 - hypot(point.x - wash.center.x, point.y - wash.center.y) / wash.radiusFraction
        return wash.color.opacity(max(0, reach))
    }
    return Ground(base: palette.paper.baseTop, layers: [palette.paper.baseBottom.opacity(point.y)] + washes)
}

/// Where Settings draws secondary text when it opens as a sheet over the stage on iPhone 17 Pro,
/// at rest at the default type size: the glyph tops of the first header where it crosses the sun's
/// centre column, the leading edge of the first row value, and the build footer's baseline.
private let settingsSheetHeader = UnitPoint(x: 0.18, y: 0.158)
private let settingsSheetFirstValue = UnitPoint(x: 0.56, y: 0.363)
private let settingsSheetFooter = UnitPoint(x: 0.5, y: 0.91)

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

private let nightOpenedSessionBorderedButtonFill = Theme.rgb(76, 81, 71)
private let dayQueueSheetFootFill = Theme.rgb(181, 209, 171)

@Test(arguments: [
    (Theme.Appearance.night, nightOpenedSessionBorderedButtonFill),
    (Theme.Appearance.day, dayQueueSheetFootFill)
])
func actionInkReadsAsTextOnItsHardestFill(appearance: Theme.Appearance, fill: Color) {
    let actionInk = Theme.palette(for: appearance).actionInk
    #expect(contrast(of: actionInk, over: Ground(base: fill, layers: [])) >= 4.5)
}

@Test(arguments: Theme.Appearance.allCases)
func secondaryTextReadsAsTextWhereTheSettingsSheetDrawsIt(appearance: Theme.Appearance) {
    let palette = Theme.palette(for: appearance)
    let firstValuePaper = paperGround(palette, at: settingsSheetFirstValue)
    let grounds = [
        paperGround(palette, at: settingsSheetHeader),
        Ground(base: firstValuePaper.base, layers: firstValuePaper.layers + [palette.surface]),
        paperGround(palette, at: settingsSheetFooter)
    ]
    for ground in grounds {
        #expect(contrast(of: palette.textSecondary, over: ground) >= 4.5)
    }
}
