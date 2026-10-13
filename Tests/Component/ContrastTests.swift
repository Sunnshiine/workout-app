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

private func paperGround(_ palette: Theme.Palette, at point: UnitPoint) -> Ground {
    let washes = palette.paper.washes.map { wash in
        let reach = 1 - hypot(point.x - wash.center.x, point.y - wash.center.y) / wash.radiusFraction
        return wash.color.opacity(max(0, reach))
    }
    return Ground(base: palette.paper.baseTop, layers: [palette.paper.baseBottom.opacity(point.y)] + washes)
}

private enum Bar: Double {
    case text = 4.5
    case nonText = 3.0
}

private struct GroundSample {
    let paperPoint: UnitPoint?
    let ground: Ground
}

private let paperGrid = (0...20).flatMap { row in
    (0...20).map { column in UnitPoint(x: Double(column) / 20, y: Double(row) / 20) }
}

private enum Surface: CaseIterable {
    case paper
    case card
    case pill
    case rail
    case railSelected
    case foot
    case focusCard
    case weekCard
    case carvedChip
    case action

    func samples(_ palette: Theme.Palette) -> [GroundSample] {
        let fills = fills(palette)
        if let base = opaqueBase(palette) {
            return [GroundSample(paperPoint: nil, ground: Ground(base: base, layers: fills))]
        }
        return paperGrid.map { point in
            let paper = paperGround(palette, at: point)
            return GroundSample(paperPoint: point, ground: Ground(base: paper.base, layers: paper.layers + fills))
        }
    }

    private func opaqueBase(_ palette: Theme.Palette) -> Color? {
        switch self {
        case .action: palette.action
        case .paper, .card, .pill, .rail, .railSelected, .foot, .focusCard, .weekCard, .carvedChip: nil
        }
    }

    private func fills(_ palette: Theme.Palette) -> [Color] {
        switch self {
        case .paper, .action: []
        case .card: [palette.surface]
        case .pill: [palette.surface, palette.pillFill]
        case .rail: [palette.surface, palette.railFill]
        case .railSelected: [palette.surface, palette.railFill, palette.railSelectedFill]
        case .foot: [palette.footFill]
        case .focusCard: [palette.lighting.focusCardFill]
        case .weekCard: [palette.weekCardShade]
        case .carvedChip: [palette.chipCarvedFill]
        }
    }
}

private enum Use {
    case text
    case ink(on: [Surface], Bar)
    case ground
    case quiet(String)

    var requirement: (surfaces: [Surface], bar: Bar)? {
        switch self {
        case .text: (Surface.allCases.filter { $0 != .action }, .text)
        case .ink(let surfaces, let bar): (surfaces, bar)
        case .ground, .quiet: nil
        }
    }
}

private let uses: [String: Use] = [
    "textPrimary": .text,
    "textSecondary": .text,
    "actionInk": .text,
    "supersetPartnerName": .ink(on: [.paper], .text),
    "actionText": .ink(on: [.action], .text),
    "stepperGlyph": .ink(on: [.pill], .nonText),
    "tileCurrentBorder": .ink(on: [.focusCard, .weekCard], .nonText),
    "danger": .ink(on: Surface.allCases.filter { $0 != .action }, .nonText),
    "action": .ink(on: [.paper, .card, .railSelected], .nonText),
    "stem": .ink(on: [.paper], .nonText),
    "leafFill": .ink(on: [.paper, .focusCard, .weekCard], .nonText),
    "budStroke": .ink(on: [.paper], .nonText),
    "prescriptionTick": .ink(on: [.rail, .railSelected], .nonText),
    "surface": .ground,
    "pillFill": .ground,
    "railFill": .ground,
    "railSelectedFill": .ground,
    "footFill": .ground,
    "sheetFill": .quiet("the core punched into a chart dot; no ink sits on it"),
    "chipCarvedFill": .ground,
    "weekCardShade": .ground,
    "tileCurrentFill": .ground,
    "leafRib": .quiet("a highlight line inside the leaf; the leaf's own fill carries the mark"),
    "budFill": .quiet("the bud's body; budStroke draws its rim against the page"),
    "budGlow": .quiet("a glow shadow around the Night bud, not a mark"),
    "futureStroke": .quiet("a deliberately faint outline for Sets not yet reached"),
    "skipStroke": .quiet("a deliberately quiet dashed outline for a skipped Set; its label says Skipped"),
    "supersetPartnerBranch": .quiet("the partner's branch, quieted on purpose so the focused branch leads"),
    "pillStroke": .quiet("a hairline edge; the pill's fill carries the shape"),
    "queueStroke": .quiet("a hairline edge; the foot pill's fill carries the shape"),
    "skipFillOverlay": .quiet("the hold-to-skip progress wash, deliberately muted and never danger"),
    "tileGhostStroke": .quiet("the dashed outline of an empty bed, quiet by design"),
    "chipCarveShadow": .quiet("an inset shadow that carves the chip"),
    "chipCarveEdge": .quiet("the highlight lip below a carved chip"),
    "chartLine": .quiet("the line joining the volume chart's dots; the dots carry the data"),
    "blockSeam": .quiet("a dotted seam between Blocks in the chart, quiet by design"),
    "birdFill": .quiet("the Sunbird illustration, decorative"),
    "birdRib": .quiet("a highlight line inside the Sunbird, decorative")
]

private struct ParkedPair: Hashable {
    let appearance: Theme.Appearance
    let role: String
    let surface: Surface
}

private let dangerCall = "whether danger stays system red or takes a Greenhouse red that holds 3:1 on every ground"
private let nightActionCall = "whether the Night action green lightens where it marks the page, the card, and the selected chip"
private let nightActionInkCall = "whether Night actionInk lightens, or the pill and rail fills dim, under the sun wash"
private let nightBranchCall = "whether Night foliage lightens or the logged branch stays under 3:1 under the sun wash"
private let nightSecondaryCall =
    "whether Night mutedNight lightens; the token sheet records it falls under 4.5:1 beneath the sun wash"

private let daySecondaryCall =
    "whether Day muted darkens, or the carved chip fill lightens, where the foot wash reaches a History chip"

private let parkedRows: [(Theme.Appearance, String, Surface, floor: Double, call: String)] = [
    (.day, "danger", .paper, floor: 1.93, dangerCall),
    (.day, "danger", .card, floor: 2.56, dangerCall),
    (.day, "danger", .rail, floor: 2.92, dangerCall),
    (.day, "danger", .foot, floor: 2.53, dangerCall),
    (.day, "danger", .weekCard, floor: 2.56, dangerCall),
    (.day, "danger", .carvedChip, floor: 1.75, dangerCall),
    (.night, "danger", .paper, floor: 2.81, dangerCall),
    (.night, "danger", .card, floor: 2.30, dangerCall),
    (.night, "danger", .pill, floor: 1.97, dangerCall),
    (.night, "danger", .rail, floor: 1.97, dangerCall),
    (.night, "danger", .railSelected, floor: 1.41, dangerCall),
    (.night, "danger", .foot, floor: 2.37, dangerCall),
    (.night, "danger", .focusCard, floor: 2.30, dangerCall),
    (.night, "danger", .weekCard, floor: 2.37, dangerCall),
    (.night, "danger", .carvedChip, floor: 2.37, dangerCall),
    (.night, "action", .paper, floor: 2.15, nightActionCall),
    (.night, "action", .card, floor: 1.76, nightActionCall),
    (.night, "action", .railSelected, floor: 1.08, nightActionCall),
    (.night, "prescriptionTick", .rail, floor: 1.51, "whether the Night prescription tick lightens off the action green"),
    (.night, "prescriptionTick", .railSelected, floor: 1.08, "whether the Night prescription tick lightens off the action green"),
    (.night, "actionText", .action, floor: 4.23, "whether the 18pt Log label counts as large text at 3:1, or the Night action darkens"),
    (.night, "actionInk", .pill, floor: 4.09, nightActionInkCall),
    (.night, "actionInk", .rail, floor: 4.09, nightActionInkCall),
    (.night, "actionInk", .railSelected, floor: 2.94, nightActionInkCall),
    (.night, "textPrimary", .railSelected, floor: 4.46, "whether the Night selected chip fill dims under the sun wash"),
    (.night, "stem", .paper, floor: 2.68, nightBranchCall),
    (.night, "leafFill", .paper, floor: 2.68, nightBranchCall),
    (.night, "leafFill", .focusCard, floor: 2.20, nightBranchCall),
    (.night, "leafFill", .weekCard, floor: 2.26, nightBranchCall),
    (.night, "textSecondary", .paper, floor: 4.08, nightSecondaryCall),
    (.night, "textSecondary", .card, floor: 3.35, nightSecondaryCall),
    (.night, "textSecondary", .pill, floor: 2.87, nightSecondaryCall),
    (.night, "textSecondary", .rail, floor: 2.87, nightSecondaryCall),
    (.night, "textSecondary", .railSelected, floor: 2.06, nightSecondaryCall),
    (.night, "textSecondary", .foot, floor: 3.45, nightSecondaryCall),
    (.night, "textSecondary", .focusCard, floor: 3.35, nightSecondaryCall),
    (.night, "textSecondary", .weekCard, floor: 3.45, nightSecondaryCall),
    (.night, "textSecondary", .carvedChip, floor: 3.45, nightSecondaryCall),
    (.day, "textSecondary", .carvedChip, floor: 4.36, daySecondaryCall),
    (.day, "actionInk", .carvedChip, floor: 4.17, "whether Day actionInk darkens under the foot wash"),
    (
        .day, "supersetPartnerName", .paper, floor: 3.40,
        "whether the partner name may sit over a wash; UI-14 measured 4.5:1 only where none reaches"
    )
]

/// A parked pair still fails its bar, so `floor` (its ratio when parked, less 0.01) is what stops it
/// sinking further unnoticed.
private let parked: [ParkedPair: (floor: Double, reason: String)] = Dictionary(
    uniqueKeysWithValues: parkedRows.map { appearance, role, surface, floor, call in
        (
            ParkedPair(appearance: appearance, role: role, surface: surface),
            (floor, "product call: palette value. The operator decides \(call).")
        )
    }
)

private func paletteInks(_ palette: Theme.Palette) -> [String: Color?] {
    Dictionary(
        uniqueKeysWithValues: Mirror(reflecting: palette).children.compactMap { child in
            guard let label = child.label, let ink = child.value as? Color? else { return nil }
            return (label, ink)
        }
    )
}

private struct WorstCase {
    let ratio: Double
    let sample: GroundSample
}

private func worstCase(of ink: Color, on surface: Surface, _ palette: Theme.Palette) -> WorstCase {
    surface.samples(palette)
        .map { WorstCase(ratio: contrast(of: ink, over: $0.ground), sample: $0) }
        .min { $0.ratio < $1.ratio }!
}

private func hex(_ color: SRGB) -> String {
    [color.red, color.green, color.blue].map { String(format: "%02X", Int($0.rounded())) }.joined()
}

private func describe(_ ink: Color) -> String {
    let (rgb, alpha) = srgbComponents(of: ink)
    return alpha < 1 ? "#\(hex(rgb)) @ \(String(format: "%.2f", alpha))" : "#\(hex(rgb))"
}

private func describe(_ sample: GroundSample) -> String {
    let ground = "#\(hex(composite(sample.ground.layers, over: sample.ground.base)))"
    guard let point = sample.paperPoint else { return "its opaque fill \(ground)" }
    return "paper (\(String(format: "%.2f", point.x)), \(String(format: "%.2f", point.y))) composited to \(ground)"
}

@Test func everyPaletteRoleHasAUse() {
    let roles = Set(paletteInks(Theme.palette(for: .day)).keys)
    let keyed = Set(uses.keys)
    #expect(roles.subtracting(keyed).sorted() == [], "palette roles with no Use")
    #expect(keyed.subtracting(roles).sorted() == [], "Use keys that name no palette role")
}

@Test(arguments: Theme.Appearance.allCases)
func everyBarredInkClearsItsBarOnEverySurfaceItIsDrawnOn(appearance: Theme.Appearance) {
    let palette = Theme.palette(for: appearance)
    let inks = paletteInks(palette)
    for (role, use) in uses.sorted(by: { $0.key < $1.key }) {
        guard let (surfaces, bar) = use.requirement, case let ink?? = inks[role] else { continue }
        for surface in surfaces {
            let worst = worstCase(of: ink, on: surface, palette)
            let measured = String(format: "%.2f", worst.ratio)
            let comment: Comment = """
                \(appearance) \(role) on \(surface): ink \(describe(ink)) over \(describe(worst.sample)) \
                measures \(measured):1, under \(bar.rawValue):1
                """
            if let park = parked[ParkedPair(appearance: appearance, role: role, surface: surface)] {
                #expect(worst.ratio >= park.floor, "parked below its floor \(park.floor):1: \(comment)")
                withKnownIssue(Comment(rawValue: park.reason)) {
                    #expect(worst.ratio >= bar.rawValue, comment)
                }
            } else {
                #expect(worst.ratio >= bar.rawValue, comment)
            }
        }
    }
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

// The matrix parks this pair at the page foot, so this upper-stage ground is its only live guard.
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

// The matrix parks Night textSecondary on paper and card, so these drawn points are its only live guard.
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
