import Foundation
import SwiftUI

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = Theme.palette(for: Theme.Appearance.day)
}

extension EnvironmentValues {
    var themePalette: Theme.Palette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

/// The single styling seam (ADR-0014). Views consume flat semantic roles from the environment
/// palette and named tokens from `Theme`; nothing styles itself outside this seam. The Greenhouse
/// system ships exactly two hand-lit appearances — `.day` and `.night`, the same room re-lit —
/// each a value sheet transcribed from `docs/design/greenhouse-theme-tokens.md`.
enum Theme {
    /// The two shipping appearances. Day is primary; Night is the same room re-lit, never
    /// recolored. There is no Day→Night derivation rule — each is hand-lit.
    enum Appearance: String, CaseIterable {
        case day
        case night
    }

    // MARK: - Paint box

    /// The small set of pigments every role is mixed from (token sheet §2). Most roles are
    /// `paint @ opacity`; wash recipes, glows and `tileCurrentBorder` are honest literals.
    enum Paint {
        static let ink = rgb(21, 33, 24) // #152118 — day text
        static let inkNight = rgb(239, 243, 227) // #EFF3E3 — night text
        static let muted = rgb(82, 100, 87) // #526457 — day secondary
        static let mutedNight = rgb(154, 170, 155) // #9AAA9B — night secondary
        static let cream = rgb(242, 247, 232) // #F2F7E8 — the workhorse
        static let actionDay = rgb(13, 107, 64) // #0D6B40 — day action / leaf / stem / bird
        static let actionNight = rgb(31, 133, 82) // #1F8552 — night action (mint is banned at night)
        static let foliage = rgb(87, 145, 104) // #579168 — the night pigment
        static let paperDayTop = rgb(233, 238, 220) // #E9EEDC
        static let paperDayBottom = rgb(203, 225, 194) // #CBE1C2
        static let paperNightTop = rgb(35, 44, 32) // #232C20
        static let paperNightBottom = rgb(18, 29, 20) // #121D14
    }

    // MARK: - Paper wash

    /// One radial light wash in the living-paper recipe. Fractions and centre come straight from
    /// the token-sheet CSS; the SwiftUI render is an elliptical approximation revalidated by the
    /// visual gate (ADR-0007).
    struct RadialWash: Equatable {
        let color: Color
        let center: UnitPoint
        let radiusFraction: Double
    }

    /// The layered living-paper recipe for one appearance: a base sage pair under four radial
    /// washes (token sheet §3, `paperWash`). Replaces the retired two-stop `gradientStops`.
    struct PaperRecipe: Equatable {
        let baseTop: Color
        let baseBottom: Color
        /// Bottom-to-top paint order (base first when rendered).
        let washes: [RadialWash]
    }

    // MARK: - Palette (flat semantic roles)

    struct Palette {
        let appearance: Appearance
        let preferredColorScheme: ColorScheme
        let paper: PaperRecipe

        // Text inks
        let textPrimary: Color
        let textSecondary: Color
        let homeBar: Color

        // Stage & branch
        let stem: Color
        let leafFill: Color
        let leafRib: Color
        let budFill: Color
        let budStroke: Color
        let budRib: Color
        let futureStroke: Color
        let skipStroke: Color

        // Active Set Card & input block
        let surface: Color
        let railFill: Color
        let prescriptionTick: Color

        // Log capsule / action
        let action: Color
        let actionText: Color

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
        let chartLine: Color
        let blockSeam: Color
        let scrim: Color
        let grabber: Color

        // Bird & colophon
        let birdFill: Color
        let birdRib: Color

        // Destructive
        let danger: Color

        // MARK: Legacy role aliases
        //
        // The existing screens (rebuilt screen-by-screen in later Greenhouse slices) still consume
        // the pre-Greenhouse role names. These map onto the reshaped seam so those compositions keep
        // compiling and simply re-light; each alias retires when its last consumer migrates.
        var accent: Color { action }
        var accentDarkText: Color { actionText }
        var progressTrack: Color { futureStroke }
        var activeCardFill: Color { surface }
        var activeCardStroke: Color { queueStroke }
        var lastPerformedCardFill: Color { footFill }
        var lastPerformedCardStroke: Color { queueStroke }
        var pillFill: Color { surface }
        var pillStroke: Color { queueStroke }
        var sessionTileComplete: Color { leafFill }
        var sessionTileIncomplete: Color { footFill }
        var sessionTileUnavailable: Color { tileGhostStroke }
        var valueText: Color { textPrimary }
        var badgeFill: Color { chipCarvedFill }
        var bannerFill: Color { surface }
        var bannerStroke: Color { queueStroke }
        var sessionTileCompleteText: Color { actionText }
        var sessionTileIncompleteText: Color { textSecondary }
        var sessionTileUnavailableText: Color { textSecondary }
        var sessionTileRestingBorder: Color { queueStroke }
    }

    // MARK: - Launch argument

    static let paletteLaunchArgument = "-WORKOUT_THEME"

    static let activeAppearance = appearance(from: ProcessInfo.processInfo.arguments)
    static let activePalette = palette(for: activeAppearance)

    static let preferredColorScheme = activePalette.preferredColorScheme
    static let danger = activePalette.danger
    static let sessionTileCurrentBorder = activePalette.tileCurrentBorder

    // MARK: - Radius family (token sheet §6)
    //
    // A named concentric family replacing the retired 8 / 16 / 28 scale. Approved pixel values are
    // kept verbatim, not rounded. `soft` belongs only to the one soft container and sheet shoulders.

    enum Radius {
        static let capsule: CGFloat = 999 // ∞ — all controls
        static let soft: CGFloat = 30 // the one soft container: Active Set Card, ceremony stats, sheets
        static let focusCard: CGFloat = 24 // the Block grid's focus card
        static let card: CGFloat = 20 // collapsed week cards
        static let rail: CGFloat = 18 // reps/RPE rails
        static let tile: CGFloat = 15 // day tiles
        static let cell: CGFloat = 14 // rail chips
        static let mini: CGFloat = 6 // week mini-chips
        static let hairline: CGFloat = 2 // grabber, home bar, prescription tick (2–3)
        static let hairlineMax: CGFloat = 3
    }

    // MARK: - Motion & haptics (token sheet §7)

    /// A cubic-bézier easing curve's two control points.
    struct BezierEase: Equatable {
        let x1: Double
        let y1: Double
        let x2: Double
        let y2: Double
    }

    /// The signature timing, confined to the three growth moments. All chrome — including the Log
    /// capsule — stays on stock system springs.
    static let wingEase = BezierEase(x1: 0.46, y1: -0.09, x2: 0.83, y2: 0.32)

    static func wingAnimation(duration: Double) -> Animation {
        .timingCurve(wingEase.x1, wingEase.y1, wingEase.x2, wingEase.y2, duration: duration)
    }

    enum Motion {
        static let leafInk = 0.42 // a leaf inks in
        static let budOpen = 0.34 // the next bud wakes…
        static let budOpenDelay = 0.26 // …starting inside the leaf's tail (One Log, One Fill)
        static let ceremonyStem = 1.0
        static let ceremonyBeat = 0.10
        static let ceremonyBird = 0.35
        static let holdToSkipReveal = 0.25 // reveal at 250ms
        static let holdToSkipCommit = 0.85 // commit at 850ms
        static let holdToSkipRetreat = 0.2
        static let holdToSkipLoggedCommit = 0.9
        static let holdToSkipSkippedCommit = 1.1
    }

    /// A Crisp haptic tuning: `intensity` and `sharpness` for a Core Haptics transient (token
    /// sheet §7). Haptics are semantic-only — never on form fields or chrome.
    struct HapticTuning: Equatable {
        let intensity: Double
        let sharpness: Double
    }

    enum Haptics {
        static let railDetentTick = HapticTuning(intensity: 0.35, sharpness: 0.85)
        static let logTap = HapticTuning(intensity: 1.0, sharpness: 0.65)
        static let skipDud = HapticTuning(intensity: 0.45, sharpness: 0.15)
        static let stepperTick = HapticTuning(intensity: 0.45, sharpness: 0.80)
    }

    // MARK: - Legacy composition constants
    //
    // Geometry and motion consumed by the pre-Greenhouse screen compositions. These keep the
    // existing screens intact until the per-screen slices migrate each onto the named tokens above;
    // each retires with its last consumer.

    static let cardCornerRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 16
    static let lensCornerRadius: CGFloat = 28
    static let sectionSpacing: CGFloat = 28
    static let supersetRestingSpacing: CGFloat = 24
    static let rowCornerRadius: CGFloat = 8
    static let sessionTileCornerRadius: CGFloat = 8
    static let sessionTileMinHeight: CGFloat = 86
    static let sessionTileSpacing: CGFloat = 10
    static let sessionTileCurrentBorderWidth: CGFloat = 1.5
    static let sessionTileUnavailableOpacity = 0.55
    static let pillCornerRadius: CGFloat = 8
    static let pillMinHeight: CGFloat = 86
    static let pillSpacing: CGFloat = 10
    static let rpeScaleHeight: CGFloat = 52
    static let rpeScaleChipWidth: CGFloat = 52
    static let rpeScaleChipSpacing: CGFloat = 6
    static let weightIncrementThreshold = 100.0
    static let lightWeightIncrementOptions = [2.5, 5.0]
    static let heavyWeightIncrementOptions = [5.0, 10.0]

    static let logButtonCheckmarkDuration = 0.2
    static let holdToSkipDuration = 0.8
    static let holdToSkipRevealDelay = 0.25
    static let holdToSkipTapMaximumDuration = 0.18
    static let momentumFlowTotalDuration = 0.65
    static let momentumDropDuration = 0.4
    static let momentumRiseDuration = 0.5
    static let momentumRiseDelay = 0.15
    static let skipFadeUpDuration = 0.45
    static let exerciseCompletionBeatDuration = 0.2
    static let focusMorphDuration = 0.28
    static let momentumSpringStiffness = 220.0
    static let momentumSpringDamping = 22.0
    static let momentumDropOffset: CGFloat = 180
    static let momentumRiseOffset: CGFloat = 44
    static let skipFadeUpOffset: CGFloat = -24
    static let exerciseRiseOffset: CGFloat = 36
    static let exerciseCompressionScale: CGFloat = 0.02
    static let pairingUnavailableOpacity = 0.3
    static let pairingConfirmationDuration = 0.22
    static let pairingConfirmationRingBleed: CGFloat = 12

    static var logButtonCheckmarkAnimation: Animation {
        .easeOut(duration: logButtonCheckmarkDuration)
    }

    static var holdToSkipProgressAnimation: Animation {
        .linear(duration: holdToSkipDuration)
    }

    static var momentumFlowAnimation: Animation {
        .easeInOut(duration: momentumFlowTotalDuration)
    }

    static var momentumDropAnimation: Animation {
        .timingCurve(0.2, 0.0, 0.12, 1.0, duration: momentumDropDuration)
    }

    static var momentumRiseAnimation: Animation {
        .interpolatingSpring(
            mass: 1,
            stiffness: momentumSpringStiffness,
            damping: momentumSpringDamping,
            initialVelocity: 0
        )
        .delay(momentumRiseDelay)
    }

    static var skipFadeUpAnimation: Animation {
        .easeOut(duration: skipFadeUpDuration)
    }

    static var exerciseCollapseAnimation: Animation {
        .easeInOut(duration: momentumDropDuration)
    }

    static var exerciseRiseAnimation: Animation {
        .easeOut(duration: momentumRiseDuration)
            .delay(exerciseCompletionBeatDuration)
    }

    static var focusMorphAnimation: Animation {
        .easeInOut(duration: focusMorphDuration)
    }
}

// MARK: - Appearance resolution

extension Theme {
    /// Resolves the `-WORKOUT_THEME` screenshot/test pin. Only `day` and `night` are accepted; the
    /// five retired legacy palette names resolve to the Day default.
    static func appearance(from arguments: [String]) -> Appearance {
        guard
            let argumentIndex = arguments.firstIndex(of: paletteLaunchArgument),
            arguments.indices.contains(arguments.index(after: argumentIndex)),
            let appearance = Appearance(rawValue: arguments[arguments.index(after: argumentIndex)])
        else {
            return .day
        }
        return appearance
    }

    /// Resolves the user's three-way preference against the current system scheme (system-dark maps
    /// to Night). "Dark" has left the product vocabulary — the forced case is Night.
    static func palette(for preference: AppearancePreference, colorScheme: ColorScheme = .light) -> Palette {
        switch preference {
        case .light:
            palette(for: .day)
        case .dark:
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
        case .dark:
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
        appearance: .day,
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
        homeBar: Paint.ink.opacity(0.20),
        stem: Paint.actionDay,
        leafFill: Paint.actionDay,
        leafRib: Paint.cream.opacity(0.50),
        budFill: Paint.cream.opacity(0.95),
        budStroke: Paint.actionDay,
        budRib: Paint.actionDay.opacity(0.55),
        futureStroke: Paint.actionDay.opacity(0.40),
        skipStroke: Paint.muted.opacity(0.42),
        surface: Paint.cream.opacity(0.52),
        railFill: Paint.cream.opacity(0.55),
        prescriptionTick: Paint.actionDay,
        action: Paint.actionDay,
        actionText: Paint.cream,
        footFill: Paint.cream.opacity(0.50),
        queueStroke: rgb(82, 111, 90, 0.38),
        tileCurrentFill: Paint.cream.opacity(0.95),
        tileCurrentBorder: rgb(31, 133, 82), // literal #1F8552 — kept exactly as approved
        tileGhostStroke: Paint.muted.opacity(0.38),
        weekCardShade: rgb(226, 233, 214, 0.72),
        sheetFill: rgb(239, 244, 228), // #EFF4E4
        chipCarvedFill: Paint.ink.opacity(0.055),
        chartLine: Paint.ink.opacity(0.35),
        blockSeam: Paint.ink.opacity(0.14),
        scrim: Paint.ink.opacity(0.32),
        grabber: Paint.ink.opacity(0.18),
        birdFill: Paint.actionDay,
        birdRib: Paint.cream.opacity(0.50),
        danger: rgb(255, 59, 48) // system red, carried forward pending danger pass
    )

    private static let nightPalette = Palette(
        appearance: .night,
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
        homeBar: Paint.cream.opacity(0.22),
        stem: Paint.foliage,
        leafFill: Paint.foliage,
        leafRib: Paint.cream.opacity(0.55),
        budFill: Paint.cream.opacity(0.92),
        budStroke: rgb(120, 240, 178), // #78F0B2 — the bud carries the page's one glow
        budRib: Paint.foliage.opacity(0.60),
        futureStroke: Paint.foliage.opacity(0.45),
        skipStroke: Paint.mutedNight.opacity(0.40),
        surface: Paint.cream.opacity(0.07),
        railFill: Paint.cream.opacity(0.06),
        prescriptionTick: Paint.actionNight,
        action: Paint.actionNight,
        actionText: Paint.cream,
        footFill: Paint.cream.opacity(0.06),
        queueStroke: Paint.cream.opacity(0.20),
        tileCurrentFill: Paint.cream.opacity(0.95),
        tileCurrentBorder: rgb(31, 133, 82), // literal #1F8552 — kept exactly as approved
        tileGhostStroke: Paint.mutedNight.opacity(0.38),
        weekCardShade: Paint.cream.opacity(0.06),
        sheetFill: rgb(31, 40, 29), // night sheet follows the #418 recipe (flagged for build validation)
        chipCarvedFill: Paint.cream.opacity(0.06),
        chartLine: Paint.inkNight.opacity(0.35),
        blockSeam: Paint.inkNight.opacity(0.14),
        scrim: rgb(9, 18, 12, 0.60),
        grabber: Paint.cream.opacity(0.18),
        birdFill: Paint.foliage,
        birdRib: Paint.cream.opacity(0.55),
        danger: rgb(255, 59, 48)
    )

    /// 0–255 sRGB channel helper so the value sheets read like the token-sheet hex/rgba literals.
    static func rgb(_ red: Double, _ green: Double, _ blue: Double, _ opacity: Double = 1) -> Color {
        Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: opacity)
    }
}

// MARK: - Living-paper background

extension Theme.Palette {
    /// The living-paper wash rendered as the background of every non-system surface (token sheet
    /// §3). One recipe per appearance; the base sage pair sits under the four radial washes.
    var paperBackground: some View {
        ZStack {
            LinearGradient(
                colors: [paper.baseTop, paper.baseBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            ForEach(Array(paper.washes.enumerated()), id: \.offset) { _, wash in
                EllipticalGradient(
                    colors: [wash.color, .clear],
                    center: wash.center,
                    startRadiusFraction: 0,
                    endRadiusFraction: wash.radiusFraction
                )
            }
        }
    }
}
