import SwiftUI
import Testing

@testable import WorkoutTracker

private enum Bar: Double {
    case text = 4.5
    case nonText = 3.0
}

private struct GroundSample {
    let paperPoint: UnitPoint
    let ground: Ground
}

private let paperGrid = (0...20).flatMap { row in
    (0...20).map { column in UnitPoint(x: Double(column) / 20, y: Double(row) / 20) }
}

private func paperGridAndWashCentres(_ palette: Theme.Palette) -> [UnitPoint] {
    paperGrid + palette.paper.washes.map(\.center).filter { (0...1).contains($0.x) && (0...1).contains($0.y) }
}

private enum SupersetStageOnIPhone17Pro {
    static let partnerNameWithTwoMoreLines = (x: 0.04...0.96, y: 0.15...0.25)
}

private enum Surface: CaseIterable {
    case paper
    case stageHeading
    case card
    case pill
    case rail
    case railSelected
    case foot
    case focusCard
    case raisedControl
    case weekCard
    case carvedChip
    case action
    case actionUnderSkipWash
    case pillUnderSkipWash

    var fillRoles: [String] {
        switch self {
        case .paper, .stageHeading: []
        case .card: ["surface"]
        case .pill: ["surface", "pillFill"]
        case .rail: ["surface", "railFill"]
        case .railSelected: ["surface", "railFill", "railSelectedFill"]
        case .foot: ["footFill"]
        case .focusCard: ["lighting.focusCardFill"]
        case .raisedControl: ["lighting.raisedControlFill"]
        case .weekCard: ["weekCardShade"]
        case .carvedChip: ["chipCarvedFill"]
        case .action: ["action"]
        case .actionUnderSkipWash: ["action", "skipFillOverlay"]
        case .pillUnderSkipWash: ["surface", "pillFill", "skipFillOverlay"]
        }
    }

    var pageRegion: (x: ClosedRange<Double>, y: ClosedRange<Double>) {
        switch self {
        case .stageHeading: SupersetStageOnIPhone17Pro.partnerNameWithTwoMoreLines
        default: (0...1, 0...1)
        }
    }

    func samples(_ palette: Theme.Palette) -> [GroundSample] {
        let inks = paletteRoles(palette).inks
        let fills = fillRoles.compactMap { inks[$0] ?? nil }
        return paperGridAndWashCentres(palette).filter { pageRegion.x.contains($0.x) && pageRegion.y.contains($0.y) }.map { point in
            let paper = paperGround(palette, at: point)
            return GroundSample(paperPoint: point, ground: Ground(base: paper.base, layers: paper.layers + fills))
        }
    }
}

private enum Use {
    case ink(on: [Surface], Bar)
    case textWithGlyphs(text: [Surface], glyphs: [Surface])
    case ground

    var requirements: [(surface: Surface, bar: Bar)] {
        switch self {
        case .ink(let surfaces, let bar): surfaces.map { ($0, bar) }
        case .textWithGlyphs(let text, let glyphs): text.map { ($0, .text) } + glyphs.map { ($0, .nonText) }
        case .ground: []
        }
    }
}

private let uses: [String: Use] = [
    "textPrimary": .ink(
        on: [
            .paper, .card, .pill, .rail, .railSelected, .foot, .focusCard, .raisedControl, .weekCard, .carvedChip,
            .pillUnderSkipWash
        ],
        .text
    ),
    "textSecondary": .ink(on: [.paper, .card, .pill, .rail, .focusCard, .raisedControl, .weekCard, .carvedChip], .text),
    "actionInk": .textWithGlyphs(text: [.paper, .card], glyphs: [.pill]),
    "supersetPartnerName": .ink(on: [.stageHeading], .text),
    "actionText": .ink(on: [.action, .actionUnderSkipWash], .text),
    "stepperGlyph": .ink(on: [.pill], .nonText),
    "tileCurrentBorder": .ink(on: [.focusCard, .weekCard], .nonText),
    "danger": .textWithGlyphs(text: [.card, .carvedChip], glyphs: [.paper, .pill, .rail]),
    "action": .textWithGlyphs(text: [.card, .carvedChip], glyphs: [.paper, .rail, .railSelected]),
    "stem": .ink(on: [.paper], .nonText),
    "leafFill": .ink(on: [.paper, .focusCard, .weekCard], .nonText),
    "budStroke": .ink(on: [.paper], .nonText),
    "prescriptionTick": .ink(on: [.rail, .railSelected], .nonText),
    "surface": .ground,
    "pillFill": .ground,
    "railFill": .ground,
    "railSelectedFill": .ground,
    "footFill": .ground,
    "chipCarvedFill": .ground,
    "weekCardShade": .ground,
    "lighting.focusCardFill": .ground,
    "lighting.raisedControlFill": .ground,
    "skipFillOverlay": .ground
]

private let quietRoles: [String: String] = [
    "sheetFill": "the core punched into a chart dot; no ink sits on it",
    "tileCurrentFill": "the current tile's body; tileCurrentBorder draws its rim against the card",
    "leafRib": "a highlight line inside the leaf; the leaf's own fill carries the mark",
    "budFill": "the bud's body; budStroke draws its rim against the page",
    "budGlow": "a glow shadow around the Night bud, not a mark",
    "futureStroke": "a deliberately faint outline for Sets not yet reached",
    "skipStroke": "a deliberately quiet dashed outline for a skipped Set; its label says Skipped",
    "supersetPartnerBranch": "the partner's branch, quieted on purpose so the focused branch leads",
    "pillStroke": "a hairline edge; the pill's fill carries the shape",
    "queueStroke": "a hairline edge or divider; the tile, banner, or row it bounds carries the shape",
    "tileGhostStroke": "the dashed outline of an empty bed, quiet by design",
    "chipCarveShadow": "an inset shadow that carves the chip",
    "chipCarveEdge": "the highlight lip below a carved chip",
    "chartLine": "the line joining the volume chart's dots; the dots carry the data",
    "blockSeam": "a dotted seam between Blocks in the chart, quiet by design",
    "birdFill": "the Sunbird illustration, decorative",
    "birdRib": "a highlight line inside the Sunbird, decorative"
]

private struct ParkedPair: Hashable {
    let appearance: Theme.Appearance
    let role: String
    let surface: Surface
}

private let dangerCall =
    "whether danger stays system red or takes a Greenhouse red that holds 4.5:1 as Developer Tools and Live Activity "
    + "lab text and 3:1 as a glyph or rim"
private let nightActionCall = "whether the Night action green lightens where it marks the page, the rail, and the selected chip"
private let actionAsTextCall =
    "whether the onboarding link, Developer Tools statuses and notes, and the Live Activity lab status keep the "
    + "action green as text or take actionInk; #841 tracks the Night link text"
private let nightBranchCall = "whether Night foliage lightens or the logged branch stays under 3:1 under the sun wash"
private let nightSecondaryCall =
    "whether Night mutedNight lightens; the token sheet records it falls under 4.5:1 beneath the sun wash"

private let nightSkipWashCall = "whether the Night hold-to-skip wash dims the Log label less as it fills"

private let daySecondaryCall =
    "whether Day muted darkens, or the carved chip fill lightens, where the foot wash reaches a History chip"

private let parkedRows: [(Theme.Appearance, String, Surface, floor: Double, call: String)] = [
    (.day, "danger", .paper, floor: 1.93, dangerCall),
    (.day, "danger", .card, floor: 2.56, dangerCall),
    (.day, "danger", .rail, floor: 2.92, dangerCall),
    (.day, "danger", .carvedChip, floor: 1.75, dangerCall),
    (.night, "danger", .paper, floor: 2.75, dangerCall),
    (.night, "danger", .card, floor: 2.26, dangerCall),
    (.night, "danger", .pill, floor: 1.93, dangerCall),
    (.night, "danger", .rail, floor: 1.93, dangerCall),
    (.night, "danger", .carvedChip, floor: 2.32, dangerCall),
    (.night, "action", .paper, floor: 2.10, nightActionCall),
    (.day, "action", .carvedChip, floor: 3.26, actionAsTextCall),
    (.night, "action", .card, floor: 1.73, actionAsTextCall),
    (.night, "action", .carvedChip, floor: 1.78, actionAsTextCall),
    (.night, "action", .rail, floor: 1.48, nightActionCall),
    (.night, "action", .railSelected, floor: 1.06, nightActionCall),
    (.night, "prescriptionTick", .rail, floor: 1.48, "whether the Night prescription tick lightens off the action green"),
    (.night, "prescriptionTick", .railSelected, floor: 1.06, "whether the Night prescription tick lightens off the action green"),
    (.night, "actionText", .action, floor: 4.23, "whether the 18pt Log label counts as large text at 3:1, or the Night action darkens"),
    (.night, "textPrimary", .railSelected, floor: 4.40, "whether the Night selected chip fill dims under the sun wash"),
    (.night, "actionText", .actionUnderSkipWash, floor: 3.53, nightSkipWashCall),
    (.night, "textPrimary", .pillUnderSkipWash, floor: 4.33, nightSkipWashCall),
    (.night, "stem", .paper, floor: 2.62, nightBranchCall),
    (.night, "leafFill", .paper, floor: 2.62, nightBranchCall),
    (.night, "leafFill", .focusCard, floor: 2.16, nightBranchCall),
    (.night, "leafFill", .weekCard, floor: 2.22, nightBranchCall),
    (.night, "textSecondary", .paper, floor: 3.99, nightSecondaryCall),
    (.night, "textSecondary", .card, floor: 3.28, nightSecondaryCall),
    (.night, "textSecondary", .pill, floor: 2.81, nightSecondaryCall),
    (.night, "textSecondary", .rail, floor: 2.81, nightSecondaryCall),
    (.night, "textSecondary", .focusCard, floor: 3.28, nightSecondaryCall),
    (.night, "textSecondary", .raisedControl, floor: 3.28, nightSecondaryCall),
    (.night, "textSecondary", .weekCard, floor: 3.38, nightSecondaryCall),
    (.night, "textSecondary", .carvedChip, floor: 3.38, nightSecondaryCall),
    (.day, "textSecondary", .carvedChip, floor: 4.36, daySecondaryCall),
    (
        .day, "supersetPartnerName", .stageHeading, floor: 4.39,
        "whether a long partner name may run under the right-hand foliage wash; it reads 4.5:1 left of it"
    )
]

private let parked: [ParkedPair: (floor: Double, reason: String)] = Dictionary(
    uniqueKeysWithValues: parkedRows.map { appearance, role, surface, floor, call in
        (
            ParkedPair(appearance: appearance, role: role, surface: surface),
            (floor, "product call: palette value. The operator decides \(call). Once it clears its bar, delete its parkedRows row.")
        )
    }
)

private let nonInkTypes: Set<ObjectIdentifier> = [
    ObjectIdentifier(ColorScheme.self),
    ObjectIdentifier(Theme.PaperRecipe.self),
    ObjectIdentifier([Theme.BoxShadow].self),
    ObjectIdentifier(Theme.RadialLight?.self)
]

private func paletteRoles(_ palette: Theme.Palette) -> (inks: [String: Color?], unclassified: [String]) {
    var inks: [String: Color?] = [:]
    var unclassified: [String] = []
    func walk(_ value: Any, prefix: String) {
        for child in Mirror(reflecting: value).children {
            guard let label = child.label else { continue }
            let type = ObjectIdentifier(Swift.type(of: child.value))
            if type == ObjectIdentifier(Color.self) || type == ObjectIdentifier(Color?.self) {
                inks.updateValue(child.value as? Color, forKey: prefix + label)
            } else if type == ObjectIdentifier(Theme.Lighting.self) {
                walk(child.value, prefix: prefix + label + ".")
            } else if !nonInkTypes.contains(type) {
                unclassified.append(prefix + label)
            }
        }
    }
    walk(palette, prefix: "")
    return (inks, unclassified)
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
    let point = sample.paperPoint
    return "paper (\(String(format: "%.2f", point.x)), \(String(format: "%.2f", point.y))) composited to \(ground)"
}

@Test(arguments: Theme.Appearance.allCases)
func everyPaletteRoleHasAUse(appearance: Theme.Appearance) {
    let (inks, unclassified) = paletteRoles(Theme.palette(for: appearance))
    let roles = Set(inks.keys)
    let keyed = Set(uses.keys).union(quietRoles.keys)
    let unmeasuredInks = uses.filter { _, use in
        if case .ground = use { false } else { use.requirements.isEmpty }
    }
    #expect(unclassified == [], "palette properties that are neither a colour role nor a known non-ink type")
    #expect(
        roles.subtracting(keyed).sorted() == [],
        "palette roles with neither a Use nor a quiet reason"
    )
    #expect(keyed.subtracting(roles).sorted() == [], "Use or quiet keys that name no palette role")
    #expect(Set(uses.keys).intersection(quietRoles.keys).sorted() == [], "roles both measured and quiet")
    #expect(unmeasuredInks.keys.sorted() == [], "inks whose Use names no Surface")
}

@Test func everyQuietRoleSaysWhyItGoesUnmeasured() {
    let thin = quietRoles.filter { $0.value.split(separator: " ").count < 4 }.map { "\($0.key): \($0.value)" }
    #expect(thin.sorted() == [], "quiet roles whose reason is too thin for a reviewer to check")
}

@Test(arguments: Theme.Appearance.allCases)
func everyGroundIsASurfaceFillAndEveryFillResolves(appearance: Theme.Appearance) {
    let inks = paletteRoles(Theme.palette(for: appearance)).inks
    let fillRoles = Set(Surface.allCases.flatMap(\.fillRoles))
    let grounds = Set(uses.compactMap { role, use in if case .ground = use { role } else { nil } })
    let quietFills = fillRoles.filter { quietRoles[$0] != nil }
    let unresolvedFills = fillRoles.filter { inks[$0] ?? nil == nil }
    #expect(grounds.subtracting(fillRoles).sorted() == [], "grounds no Surface fills")
    #expect(quietFills.sorted() == [], "Surface fills classed quiet")
    #expect(unresolvedFills.sorted() == [], "Surface fills that resolve to no colour")
}

@Test func everySurfaceIsADistinctGroundSomeInkIsDrawnOn() {
    let drawnOn = Set(uses.values.flatMap { $0.requirements.map(\.surface) })
    let grounds = Dictionary(grouping: Surface.allCases) { "\($0.fillRoles) in \($0.pageRegion)" }
    #expect(Surface.allCases.filter { !drawnOn.contains($0) }.map { "\($0)" } == [], "Surfaces no Use draws an ink on")
    #expect(
        grounds.values.filter { $0.count > 1 }.map { $0.map { "\($0)" }.joined(separator: " = ") }.sorted() == [],
        "Surfaces that measure the same ground"
    )
}

@Test func everyParkedPairIsOneTheMatrixMeasures() {
    let measured = Set(
        Theme.Appearance.allCases.flatMap { appearance in
            uses.flatMap { role, use in
                use.requirements.map { ParkedPair(appearance: appearance, role: role, surface: $0.surface) }
            }
        }
    )
    let unmeasured = parked.keys.filter { !measured.contains($0) }.map { "\($0.appearance) \($0.role) on \($0.surface)" }
    #expect(unmeasured.sorted() == [], "parked pairs no view draws")
}

@Test(arguments: Theme.Appearance.allCases)
func everyBarredInkClearsItsBarOnEverySurfaceItIsDrawnOn(appearance: Theme.Appearance) {
    let palette = Theme.palette(for: appearance)
    let inks = paletteRoles(palette).inks
    for (role, use) in uses.sorted(by: { $0.key < $1.key }) {
        guard case let ink?? = inks[role] else { continue }
        for (surface, bar) in use.requirements {
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
