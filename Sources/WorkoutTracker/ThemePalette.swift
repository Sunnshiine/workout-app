import SwiftUI

extension Theme {
    // MARK: - Palette (flat semantic roles)

    struct Palette {
        let preferredColorScheme: ColorScheme
        let paper: PaperRecipe

        // Text inks
        let textPrimary: Color
        let textSecondary: Color
        let actionInk: Color

        // Stage & branch
        let stem: Color
        let leafFill: Color
        let leafRib: Color
        let budFill: Color
        let budStroke: Color
        let futureStroke: Color
        let skipStroke: Color
        /// The page's one glow: the active bud is lit at Night, unlit by Day (nil).
        let budGlow: Color?
        let supersetPartnerBranch: Color
        let supersetPartnerName: Color

        // Active Set Card & input block
        let surface: Color
        let surfaceShadow: [BoxShadow]
        let pillFill: Color
        let pillStroke: Color
        let stepperGlyph: Color
        let railFill: Color
        /// The selected rail chip's cream fill, lit under the inset action ring (token sheet
        /// §Active Set Card, "rail chip selected").
        let railSelectedFill: Color
        let prescriptionTick: Color

        // Log capsule / action
        let action: Color
        let actionText: Color
        /// The Log capsule's elevation: a day green drop; at Night a green light (glow, no drop).
        let logShadow: [BoxShadow]
        let skipFillOverlay: Color?

        // Stage foot
        let footFill: Color
        let queueStroke: Color

        // Block grid
        let tileCurrentFill: Color
        let tileCurrentBorder: Color
        let tileGhostStroke: Color
        let weekCardShade: Color

        // Exercise History sheet
        let sheetFill: Color
        let chipCarvedFill: Color
        let chipCarveShadow: Color
        /// The carve's light bottom edge (`0 1px 0 rgba(255,255,255,0.6)`), the highlight lip below
        /// the pressed fill; cream-toned at Night.
        let chipCarveEdge: Color
        let chartLine: Color
        let blockSeam: Color

        // Bird & colophon
        let birdFill: Color
        let birdRib: Color

        // Destructive
        let danger: Color

        let lighting: Lighting

        // MARK: Legacy role aliases
        //
        // The existing screens (rebuilt screen-by-screen in later Greenhouse slices) still consume
        // the pre-Greenhouse role names. These map onto the reshaped seam so those compositions keep
        // compiling and simply re-light; each alias retires when its last consumer migrates.
        var accent: Color { action }
        var progressTrack: Color { futureStroke }
        var sessionTileComplete: Color { leafFill }
        var valueText: Color { textPrimary }
        var badgeFill: Color { chipCarvedFill }
        var bannerFill: Color { surface }
        var bannerStroke: Color { queueStroke }

        /// The retired two-stop `gradientStops` background, re-expressed as the living-paper base
        /// pair so un-rebuilt screens keep a page background and simply re-light. The full four-wash
        /// paper (`paperBackground`) lands with each composition slice; this alias retires with the
        /// last `.gradient` consumer.
        var gradient: LinearGradient {
            LinearGradient(
                colors: [paper.baseTop, paper.baseBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Lighting

extension Theme {
    struct Lighting: Equatable {
        let pageSunbeam: RadialLight?
        let tileTopLight: RadialLight?
        let focusCardFill: Color
        let focusCardElevation: [BoxShadow]
        let raisedControlFill: Color
        let raisedControlShadow: [BoxShadow]
        let currentTileGlow: [BoxShadow]

        static let day = Lighting(
            pageSunbeam: RadialLight(
                stops: [
                    Gradient.Stop(color: rgb(253, 254, 242, 0.85), location: 0),
                    Gradient.Stop(color: rgb(250, 252, 238, 0.28), location: 0.46),
                    Gradient.Stop(color: .clear, location: 0.70)
                ],
                center: UnitPoint(x: 0.82, y: -0.08),
                radiusFraction: 0.85
            ),
            tileTopLight: RadialLight(
                stops: [
                    Gradient.Stop(color: rgb(255, 255, 245, 0.85), location: 0),
                    Gradient.Stop(color: .clear, location: 0.55)
                ],
                center: UnitPoint(x: 0.78, y: -0.30),
                radiusFraction: 0.55
            ),
            focusCardFill: rgb(248, 251, 238, 0.96),
            focusCardElevation: LightKit.cardLow + [
                BoxShadow(y: 0, blur: 0, spread: 5, color: rgb(250, 252, 238, 0.5)),
                BoxShadow(y: 6, blur: 30, color: rgb(228, 240, 200, 0.95))
            ],
            raisedControlFill: Paint.cream.opacity(0.90),
            raisedControlShadow: LightKit.cardLow,
            currentTileGlow: [
                BoxShadow(y: 0, blur: 0, spread: 4, color: rgb(242, 247, 232, 0.45)),
                BoxShadow(y: 2, blur: 18, color: rgb(220, 235, 190, 0.9))
            ]
        )

        static let night = Lighting(
            pageSunbeam: nil,
            tileTopLight: nil,
            focusCardFill: nightSurface,
            focusCardElevation: nightSurfaceShadow,
            raisedControlFill: nightSurface,
            raisedControlShadow: nightSurfaceShadow,
            currentTileGlow: [BoxShadow(y: 0, blur: 14, color: nightBudGlow)]
        )
    }

    private static let nightSurface = Paint.cream.opacity(0.07)
    private static let nightSurfaceShadow = [
        BoxShadow(y: 0, blur: 0, spread: 1, color: Paint.cream.opacity(0.10), inset: true)
    ]
    private static let nightBud = rgb(120, 240, 178)  // #78F0B2 — the bud carries the page's one glow
    private static let nightBudGlow = rgb(120, 240, 178, 0.32)
}

// MARK: - Appearance resolution

extension Theme {
    static func palette(for preference: AppearancePreference, colorScheme: ColorScheme = .light) -> Palette {
        switch preference {
        case .light:
            palette(for: .day)
        case .night:
            palette(for: .night)
        case .system:
            switch colorScheme {
            case .light:
                palette(for: .day)
            case .dark:
                palette(for: .night)
            @unknown default:
                palette(for: .day)
            }
        }
    }

    static func colorSchemeOverride(for preference: AppearancePreference) -> ColorScheme? {
        switch preference {
        case .system:
            nil
        case .light:
            .light
        case .night:
            .dark
        }
    }

    static func palette(for appearance: Appearance) -> Palette {
        switch appearance {
        case .day:
            dayPalette
        case .night:
            nightPalette
        }
    }

    // MARK: - Hand-lit value sheets

    private static let dayPalette = Palette(
        preferredColorScheme: .light,
        paper: PaperRecipe(
            baseTop: Paint.paperDayTop,
            baseBottom: Paint.paperDayBottom,
            washes: [
                RadialWash(color: rgb(255, 250, 224, 0.85), center: UnitPoint(x: 0.18, y: 0.04), radiusFraction: 0.54),
                RadialWash(color: rgb(163, 205, 154, 0.55), center: UnitPoint(x: 1.08, y: 0.32), radiusFraction: 0.49),
                RadialWash(color: rgb(214, 232, 197, 0.70), center: UnitPoint(x: -0.10, y: 0.62), radiusFraction: 0.52),
                RadialWash(color: rgb(151, 189, 140, 0.75), center: UnitPoint(x: 0.55, y: 1.08), radiusFraction: 0.77)
            ]
        ),
        textPrimary: Paint.ink,
        textSecondary: Paint.muted,
        actionInk: Paint.actionDayInk,
        stem: Paint.actionDay,
        leafFill: Paint.actionDay,
        leafRib: Paint.cream.opacity(0.50),
        budFill: Paint.cream.opacity(0.95),
        budStroke: Paint.actionDay,
        futureStroke: Paint.actionDay.opacity(0.40),
        skipStroke: Paint.muted.opacity(0.42),
        budGlow: nil,
        supersetPartnerBranch: Paint.foliage,  // Day quiets the partner by pigment
        supersetPartnerName: Paint.foliageDeep,

        surface: Paint.cream.opacity(0.52),
        surfaceShadow: [
            BoxShadow(y: 1, blur: 2, color: rgb(21, 33, 24, 0.04)),
            BoxShadow(y: 14, blur: 30, color: rgb(21, 33, 24, 0.07))
        ],
        pillFill: Paint.cream.opacity(0.85),
        pillStroke: rgb(82, 111, 90, 0.34),
        stepperGlyph: Paint.actionDay,
        railFill: Paint.cream.opacity(0.55),
        railSelectedFill: Paint.cream.opacity(0.95),
        prescriptionTick: Paint.actionDay,
        action: Paint.actionDay,
        actionText: Paint.cream,
        logShadow: [
            BoxShadow(y: 1, blur: 2, color: rgb(13, 46, 28, 0.22)),
            BoxShadow(y: 10, blur: 22, color: rgb(13, 60, 35, 0.16))
        ],
        skipFillOverlay: Paint.muted.opacity(0.30),
        footFill: Paint.cream.opacity(0.50),
        queueStroke: rgb(82, 111, 90, 0.38),
        tileCurrentFill: Paint.cream.opacity(0.95),
        tileCurrentBorder: rgb(31, 133, 82),  // literal #1F8552 — kept exactly as approved
        tileGhostStroke: Paint.muted.opacity(0.38),
        weekCardShade: rgb(226, 233, 214, 0.72),
        sheetFill: rgb(239, 244, 228),  // #EFF4E4
        chipCarvedFill: Paint.ink.opacity(0.055),
        chipCarveShadow: rgb(21, 33, 24, 0.14),  // inset top shadow — carves the chip below flat
        chipCarveEdge: Color.white.opacity(0.6),  // the light bottom lip
        chartLine: Paint.ink.opacity(0.35),
        blockSeam: Paint.ink.opacity(0.14),
        birdFill: Paint.actionDay,
        birdRib: Paint.cream.opacity(0.50),
        danger: rgb(255, 59, 48),  // system red, carried forward pending danger pass
        lighting: .day
    )

    private static let nightPalette = Palette(
        preferredColorScheme: .dark,
        paper: PaperRecipe(
            baseTop: Paint.paperNightTop,
            baseBottom: Paint.paperNightBottom,
            washes: [
                RadialWash(color: rgb(255, 233, 170, 0.14), center: UnitPoint(x: 0.18, y: 0.04), radiusFraction: 0.48),
                RadialWash(color: rgb(87, 145, 104, 0.16), center: UnitPoint(x: 1.08, y: 0.32), radiusFraction: 0.49),
                RadialWash(color: rgb(87, 145, 104, 0.10), center: UnitPoint(x: -0.10, y: 0.62), radiusFraction: 0.52),
                RadialWash(color: rgb(9, 18, 12, 0.70), center: UnitPoint(x: 0.55, y: 1.08), radiusFraction: 0.77)
            ]
        ),
        textPrimary: Paint.inkNight,
        textSecondary: Paint.mutedNight,
        actionInk: Paint.actionNightInk,
        stem: Paint.foliage,
        leafFill: Paint.foliage,
        leafRib: Paint.cream.opacity(0.55),
        budFill: Paint.cream.opacity(0.92),
        budStroke: nightBud,
        futureStroke: Paint.foliage.opacity(0.45),
        skipStroke: Paint.mutedNight.opacity(0.40),
        budGlow: nightBudGlow,
        supersetPartnerBranch: Paint.foliage.opacity(0.55),  // Night quiets the partner by translucency
        supersetPartnerName: Paint.mutedNightLight,
        surface: nightSurface,
        surfaceShadow: nightSurfaceShadow,
        pillFill: Paint.cream.opacity(0.06),
        pillStroke: Paint.cream.opacity(0.16),
        stepperGlyph: Paint.cream,
        railFill: Paint.cream.opacity(0.06),
        railSelectedFill: Paint.cream.opacity(0.14),
        prescriptionTick: Paint.actionNight,
        action: Paint.actionNight,
        actionText: Paint.cream,
        logShadow: [
            BoxShadow(y: 0, blur: 22, color: rgb(31, 133, 82, 0.35))  // green light — glow, no drop
        ],
        skipFillOverlay: Paint.mutedNight.opacity(0.30),  // muted hold-to-skip overlay, re-lit for Night (#488)
        footFill: Paint.cream.opacity(0.06),
        queueStroke: Paint.cream.opacity(0.20),
        tileCurrentFill: Paint.foliage,
        tileCurrentBorder: nightBud,
        tileGhostStroke: Paint.mutedNight.opacity(0.38),
        weekCardShade: Paint.cream.opacity(0.06),
        sheetFill: rgb(31, 40, 29),  // night sheet follows the #418 recipe (flagged for build validation)
        chipCarvedFill: Paint.cream.opacity(0.06),
        chipCarveShadow: rgb(9, 18, 12, 0.45),  // deep sage-ink inset — the room re-lit, never black
        chipCarveEdge: Paint.cream.opacity(0.10),  // cream-toned bottom lip at Night
        chartLine: Paint.inkNight.opacity(0.35),
        blockSeam: Paint.inkNight.opacity(0.14),
        birdFill: Paint.foliage,
        birdRib: Paint.cream.opacity(0.55),
        danger: rgb(255, 59, 48),
        lighting: .night
    )

    /// 0–255 sRGB channel helper so the value sheets read like the token-sheet hex/rgba literals.
    static func rgb(_ red: Double, _ green: Double, _ blue: Double, _ opacity: Double = 1) -> Color {
        Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: opacity)
    }
}
