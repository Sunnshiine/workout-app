import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

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
    enum Appearance: CaseIterable {
        case day
        case night
    }

    // MARK: - Radius family (token sheet §6)
    //
    // A named concentric family replacing the retired 8 / 16 / 28 scale. Approved pixel values are
    // kept verbatim, not rounded. A container's radius is its corner child's radius plus the inset
    // between them, so the two curves stay concentric. Sheets take the system's own corners.

    enum Radius {
        static let capsule: CGFloat = 999  // ∞ — all controls
        static let soft: CGFloat = 30  // ceremony stats and the Settings confirmation card
        // Concentric with the Log capsule at its corner: the capsule's measured ~29pt half-height plus
        // the card's 14pt bottom inset.
        static let activeSetCard: CGFloat = 43
        // Concentric with the day tiles inside it: tile 15 + the card's 16pt `blockFocusCardPadding`.
        static let focusCard: CGFloat = 31
        // Collapsed week cards, already concentric: mini 6 + the 14pt `blockWeekCardPadding`.
        static let card: CGFloat = 20
        static let rail: CGFloat = 18  // reps/RPE rails
        static let tile: CGFloat = 15  // day tiles
        static let cell: CGFloat = 14  // rail chips
        static let mini: CGFloat = 6  // week mini-chips
    }

    // MARK: - Motion & haptics (token sheet §7)

    /// A cubic-bézier easing curve's two control points.
    struct BezierEase: Equatable {
        let x1: Double
        let y1: Double
        let x2: Double
        let y2: Double
    }

    /// The signature timing, drawn from the Sunbird's wing. It eases in, so it is the Move On
    /// ceremony's alone, the one moment slow enough to carry it.
    static let wingEase = BezierEase(x1: 0.46, y1: -0.09, x2: 0.83, y2: 0.32)

    /// A strong ease-out for the moments a log causes. The leaf moves on the frame the log's haptic
    /// lands, and settles slowly enough to read.
    static let inkEase = BezierEase(x1: 0.23, y1: 1, x2: 0.32, y2: 1)

    static func inkAnimation(duration: Double) -> Animation {
        .timingCurve(inkEase.x1, inkEase.y1, inkEase.x2, inkEase.y2, duration: duration)
    }

    enum BranchGrowth {
        case leafInk
        case budWake
        case budLift
        case relayout

        fileprivate var motion: Animation {
            switch self {
            case .leafInk: Theme.inkAnimation(duration: Motion.leafInk)
            case .budWake: Theme.inkAnimation(duration: Motion.budOpen).delay(Motion.budOpenDelay)
            case .budLift: Theme.inkAnimation(duration: Motion.budOpenDelay)
            case .relayout: .smooth(duration: Motion.leafInk)
            }
        }

        fileprivate var crossfade: Animation? {
            switch self {
            case .leafInk, .budLift: .easeInOut(duration: Motion.crossfade)
            case .budWake: .easeInOut(duration: Motion.crossfade).delay(Motion.crossfade)
            case .relayout: nil
            }
        }
    }

    static func branchAnimation(_ growth: BranchGrowth, reducingMotion: Bool) -> Animation? {
        reducingMotion ? growth.crossfade : growth.motion
    }

    enum Motion {
        static let leafInk = 0.3  // a leaf inks in
        static let budOpen = 0.3  // the next bud wakes…
        static let budOpenDelay = 0.12  // …starting inside the leaf's tail (One Log, One Fill)
        static let crossfade = 0.2
        static let ceremonyStem = 1.0
        static let ceremonyBeat = 0.10
        static let ceremonyBird = 0.35
        static let holdToSkipReveal = 0.25  // reveal at 250ms
        static let holdToSkipCommit = 0.85  // commit at 850ms
        static let holdToSkipRetreat = 0.2
        static let holdToSkipLoggedCommit = 0.9  // logged-state hold
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

    // MARK: - Block grid geometry (Greenhouse §5.5)
    //
    // The focus-week grid: wordless, wider-than-tall tiles whose fill + stroke alone say state.
    // Geometry constants (not palette); the named radius family owns the corners.

    static let blockTileHeight: CGFloat = 52  // full day tile — wider-than-tall
    static let blockTileMiniHeight: CGFloat = 16  // collapsed card's mini day-strip
    static let blockTileSpacing: CGFloat = 10
    static let blockTileMiniSpacing: CGFloat = 5
    static let blockTileStroke: CGFloat = 1  // quiet available / mini strokes
    static let blockTileCurrentStroke: CGFloat = 1.5  // the current tile's rim
    static let blockTileGhostStroke: CGFloat = 1.5  // the empty bed's dashed outline
    static let blockTileGhostDash: CGFloat = 4
    static let blockWeekCardPadding: CGFloat = 14
    static let blockFocusCardPadding: CGFloat = 16

    // MARK: - Sheet tab Day cards
    //
    // The Day sections of the Sheet tab the Block grid opens. Every column of a Day fits its card:
    // number columns hold their minimum and the name and notes columns take what is left.

    static let sheetNameColumnMinWidth: Double = 80
    static let sheetNotesColumnMinWidth: Double = 56
    static let sheetValueColumnMinWidth: Double = 40
    /// A row's floor; a value that wraps grows it.
    static let sheetRowHeight: CGFloat = 36
    /// Lines a cell wraps to before it truncates; tapping shows the rest.
    static let sheetCellLineLimit = 3
    static let sheetCellVerticalInset: CGFloat = 6
    static let sheetCellInset: CGFloat = 4
    static let sheetHairline: CGFloat = 0.5
    static let sheetSelectedCellStroke: CGFloat = 1.5
    static let sheetHiddenRowOpacity: Double = 0.45  // dimmed, never dropped

    static let pageMargin: CGFloat = 16  // the one left edge every session and progress page aligns to
    static let cardSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
    static let editingWeightFootGap: CGFloat = 10
    static let stageColumnSpacing: CGFloat = 14
    static let stageBranchTopPadding: CGFloat = 4

    // MARK: - Active Set Card & input block geometry
    //
    // Type-coupled geometry kept in Theme so it graduates to @ScaledMetric in one place if the
    // fixed-size stance ever reverses. Radii come from the named family; these are the sizes.

    static let cardContentPadding = EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16)
    static let inputBlockSpacing: CGFloat = 16
    static let weightStepperDiameter: CGFloat = 54  // the round ± steppers flanking the weight
    static let railCellWidth: CGFloat = 48  // one rail chip cell (48×44)
    static let railCellHeight: CGFloat = 44
    static let railTrackHeight: CGFloat = 58  // the rail track the cells sit inside, concentric with cell 14
    static let railCellInset: CGFloat = 3  // the selected chip's inset within its cell
    static let railEdgeFadeWidth: CGFloat = 18
    static let prescriptionTickWidth: CGFloat = 18  // last-week tick under the rail value (18×3, r2)
    static let prescriptionTickHeight: CGFloat = 3

    static let holdToSkipTapMaximumDuration = 0.18  // a release this soon is the Log tap
    static let holdToSkipTapSuppression = 0.25  // a tap this soon after a cancelled hold or a skip is its release
    static let sessionMotionDuration = 0.3
    static let stageCompositionDuration = 0.25
    static let pairingUnavailableOpacity = 0.3
    static let pairingConfirmationDuration = 0.22

    /// What a log, a skip, or a tap on a Set moves outside the branch and the card: one critically
    /// damped spring inside the Set's 0.42 s budget (DESIGN.md §7).
    static var sessionMotionAnimation: Animation {
        .smooth(duration: sessionMotionDuration)
    }

    static var stageCompositionAnimation: Animation {
        .easeInOut(duration: stageCompositionDuration)
    }

    /// The press on the Log capsule, the weight steppers, and every primary capsule (§5.2, §5.3, §7):
    /// a system snappy spring from touch-down until the finger lifts.
    static let pressScale = 0.97
    static var pressAnimation: Animation {
        .snappy(duration: 0.16)
    }
}

#if canImport(UIKit)
    extension Theme {
        static let selectedSegmentFill = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(palette(for: .night).actionFill) : .white
        }
    }
#endif
