import SwiftUI
import Testing

@testable import WorkoutTracker

struct SRGB {
    let red: Double
    let green: Double
    let blue: Double
}

func srgbComponents(of color: Color) -> (rgb: SRGB, alpha: Double) {
    let resolved = color.resolve(in: EnvironmentValues())
    let rgb = SRGB(
        red: Double(resolved.red) * 255,
        green: Double(resolved.green) * 255,
        blue: Double(resolved.blue) * 255
    )
    return (rgb, Double(resolved.opacity))
}

func composite(_ layers: [Color], over ground: Color) -> SRGB {
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

struct Ground {
    let base: Color
    let layers: [Color]
}

func contrast(of mark: Color, over ground: Ground) -> Double {
    let lighter = relativeLuminance(composite(ground.layers + [mark], over: ground.base))
    let darker = relativeLuminance(composite(ground.layers, over: ground.base))
    return (max(lighter, darker) + 0.05) / (min(lighter, darker) + 0.05)
}

func paperGround(_ palette: Theme.Palette, at point: UnitPoint) -> Ground {
    let washes = palette.paper.washes.map { wash in
        let reach = 1 - hypot(point.x - wash.center.x, point.y - wash.center.y) / wash.radiusFraction
        return wash.color.opacity(max(0, reach))
    }
    return Ground(base: palette.paper.baseTop, layers: [palette.paper.baseBottom.opacity(point.y)] + washes)
}

private enum SettingsSheetAtRestOnIPhone17Pro {
    static let headerGlyphTop = UnitPoint(x: 0.18, y: 0.158)
    static let firstValue = UnitPoint(x: 0.56, y: 0.363)
    static let footer = UnitPoint(x: 0.5, y: 0.91)
}

@Test func paletteTokensResolveToTheirSRGBChannels() {
    let ink = srgbComponents(of: Theme.Paint.ink).rgb
    #expect(abs(ink.red - 21) <= 0.5 && abs(ink.green - 33) <= 0.5 && abs(ink.blue - 24) <= 0.5)
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
    let firstValuePaper = paperGround(palette, at: SettingsSheetAtRestOnIPhone17Pro.firstValue)
    let grounds = [
        paperGround(palette, at: SettingsSheetAtRestOnIPhone17Pro.headerGlyphTop),
        Ground(base: firstValuePaper.base, layers: firstValuePaper.layers + [palette.surface]),
        paperGround(palette, at: SettingsSheetAtRestOnIPhone17Pro.footer)
    ]
    for ground in grounds {
        #expect(contrast(of: palette.textSecondary, over: ground) >= 4.5)
    }
}
