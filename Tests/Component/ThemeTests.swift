import SwiftUI
import Testing

@testable import WorkoutTracker

#if canImport(AppKit)
    import AppKit
#endif

#if canImport(AppKit)
    private struct RGBAComponents {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    private func rgbaComponents(of color: Color) -> RGBAComponents? {
        NSColor(color).usingColorSpace(.deviceRGB).map {
            RGBAComponents(
                red: Double($0.redComponent),
                green: Double($0.greenComponent),
                blue: Double($0.blueComponent),
                alpha: Double($0.alphaComponent)
            )
        }
    }

    private func expectRGB(
        _ color: Color,
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let rgb = rgbaComponents(of: color) else {
            Issue.record("Could not resolve color to deviceRGB", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(rgb.red - red) < 0.01, "Expected red ≈ \(red), got \(rgb.red)", sourceLocation: sourceLocation)
        #expect(abs(rgb.green - green) < 0.01, "Expected green ≈ \(green), got \(rgb.green)", sourceLocation: sourceLocation)
        #expect(abs(rgb.blue - blue) < 0.01, "Expected blue ≈ \(blue), got \(rgb.blue)", sourceLocation: sourceLocation)
        if let alpha {
            #expect(abs(rgb.alpha - alpha) < 0.01, "Expected alpha ≈ \(alpha), got \(rgb.alpha)", sourceLocation: sourceLocation)
        }
    }
#endif

// MARK: - Appearances

@Test func themeShipsExactlyTwoAppearances() {
    #expect(Theme.Appearance.allCases == [.day, .night])
}

@Test func themeDayAppearanceIsLightNightIsDark() {
    #expect(Theme.palette(for: Theme.Appearance.day).preferredColorScheme == .light)
    #expect(Theme.palette(for: Theme.Appearance.night).preferredColorScheme == .dark)
    #expect(Theme.palette(for: Theme.Appearance.day).appearance == .day)
    #expect(Theme.palette(for: Theme.Appearance.night).appearance == .night)
}

// MARK: - Appearance resolution (preference × system scheme)

@Test func themeResolvesLightPreferenceToDayAndNightPreferenceToNight() {
    #expect(Theme.palette(for: AppearancePreference.light).appearance == .day)
    #expect(Theme.palette(for: AppearancePreference.dark).appearance == .night)
}

@Test func themeSystemPreferenceFollowsColorSchemeAndSystemDarkMapsToNight() {
    #expect(Theme.palette(for: AppearancePreference.system, colorScheme: .light).appearance == .day)
    #expect(Theme.palette(for: AppearancePreference.system, colorScheme: .dark).appearance == .night)
}

@Test func themeForcedPreferencesIgnoreCurrentColorScheme() {
    #expect(Theme.palette(for: AppearancePreference.light, colorScheme: .dark).appearance == .day)
    #expect(Theme.palette(for: AppearancePreference.dark, colorScheme: .light).appearance == .night)
}

@Test func themeColorSchemeOverrideOnlyForForcedPreferences() {
    #expect(Theme.colorSchemeOverride(for: AppearancePreference.system) == nil)
    #expect(Theme.colorSchemeOverride(for: AppearancePreference.light) == .light)
    #expect(Theme.colorSchemeOverride(for: AppearancePreference.dark) == .dark)
}

// MARK: - Launch-argument parsing

@Test func themeLaunchArgumentAcceptsOnlyDayAndNight() {
    #expect(Theme.appearance(from: ["WorkoutTracker", Theme.paletteLaunchArgument, "day"]) == .day)
    #expect(Theme.appearance(from: ["WorkoutTracker", Theme.paletteLaunchArgument, "night"]) == .night)
}

@Test func themeLaunchArgumentDefaultsToDayWhenMissingOrUnknown() {
    #expect(Theme.appearance(from: ["WorkoutTracker"]) == .day)
    #expect(Theme.appearance(from: ["WorkoutTracker", Theme.paletteLaunchArgument]) == .day)
    #expect(Theme.appearance(from: ["WorkoutTracker", Theme.paletteLaunchArgument, "unknown"]) == .day)
}

@Test func themeLaunchArgumentRejectsTheFiveRetiredPalettes() {
    for retired in ["dark", "black", "mintGreen", "sageLight", "blueLight"] {
        #expect(
            Theme.appearance(from: ["WorkoutTracker", Theme.paletteLaunchArgument, retired]) == .day,
            "\(retired) is a retired legacy palette and must not resolve to a shipping appearance"
        )
    }
}

// MARK: - Paint box (token sheet §2)

@Test func themePaintBoxMatchesTokenSheet() {
    #if canImport(AppKit)
        expectRGB(Theme.Paint.ink, red: 21 / 255, green: 33 / 255, blue: 24 / 255)
        expectRGB(Theme.Paint.inkNight, red: 239 / 255, green: 243 / 255, blue: 227 / 255)
        expectRGB(Theme.Paint.muted, red: 82 / 255, green: 100 / 255, blue: 87 / 255)
        expectRGB(Theme.Paint.mutedNight, red: 154 / 255, green: 170 / 255, blue: 155 / 255)
        expectRGB(Theme.Paint.cream, red: 242 / 255, green: 247 / 255, blue: 232 / 255)
        expectRGB(Theme.Paint.actionDay, red: 13 / 255, green: 107 / 255, blue: 64 / 255)
        expectRGB(Theme.Paint.actionNight, red: 31 / 255, green: 133 / 255, blue: 82 / 255)
        expectRGB(Theme.Paint.foliage, red: 87 / 255, green: 145 / 255, blue: 104 / 255)
    #endif
}

// MARK: - Paper wash (token sheet §3)

@Test func themePaperRecipesUseTheHandLitBasePairs() {
    #if canImport(AppKit)
        let day = Theme.palette(for: Theme.Appearance.day).paper
        expectRGB(day.baseTop, red: 233 / 255, green: 238 / 255, blue: 220 / 255)
        expectRGB(day.baseBottom, red: 203 / 255, green: 225 / 255, blue: 194 / 255)
        #expect(day.washes.count == 4)

        let night = Theme.palette(for: Theme.Appearance.night).paper
        expectRGB(night.baseTop, red: 35 / 255, green: 44 / 255, blue: 32 / 255)
        expectRGB(night.baseBottom, red: 18 / 255, green: 29 / 255, blue: 20 / 255)
        #expect(night.washes.count == 4)
    #endif
}

@Test func themeDayPaperTopWashIsTheWarmSunWash() {
    #if canImport(AppKit)
        let warmSun = Theme.palette(for: Theme.Appearance.day).paper.washes[0]
        expectRGB(warmSun.color, red: 255 / 255, green: 250 / 255, blue: 224 / 255, alpha: 0.85)
        #expect(warmSun.center == UnitPoint(x: 0.18, y: 0.04))
    #endif
}

// MARK: - Semantic roles (token sheet §3)

@Test func themeActionRoleIsHandLitGreenPerAppearance() {
    #if canImport(AppKit)
        expectRGB(Theme.palette(for: Theme.Appearance.day).action, red: 13 / 255, green: 107 / 255, blue: 64 / 255)
        expectRGB(Theme.palette(for: Theme.Appearance.night).action, red: 31 / 255, green: 133 / 255, blue: 82 / 255)
    #endif
}

@Test func themeTextInksMatchTokenSheet() {
    #if canImport(AppKit)
        let day = Theme.palette(for: Theme.Appearance.day)
        expectRGB(day.textPrimary, red: 21 / 255, green: 33 / 255, blue: 24 / 255)
        expectRGB(day.textSecondary, red: 82 / 255, green: 100 / 255, blue: 87 / 255)

        let night = Theme.palette(for: Theme.Appearance.night)
        expectRGB(night.textPrimary, red: 239 / 255, green: 243 / 255, blue: 227 / 255)
        expectRGB(night.textSecondary, red: 154 / 255, green: 170 / 255, blue: 155 / 255)
    #endif
}

@Test func themeSurfaceIsCreamAtHandLitOpacity() {
    #if canImport(AppKit)
        expectRGB(
            Theme.palette(for: Theme.Appearance.day).surface,
            red: 242 / 255, green: 247 / 255, blue: 232 / 255, alpha: 0.52
        )
        expectRGB(
            Theme.palette(for: Theme.Appearance.night).surface,
            red: 242 / 255, green: 247 / 255, blue: 232 / 255, alpha: 0.07
        )
    #endif
}

@Test func themeNightBudStrokeCarriesTheOneGlowGreen() {
    #if canImport(AppKit)
        expectRGB(Theme.palette(for: Theme.Appearance.night).budStroke, red: 120 / 255, green: 240 / 255, blue: 178 / 255)
    #endif
}

@Test func themeTileCurrentBorderStaysTheApprovedLiteral() {
    // #1F8552 in both appearances — deliberately not aliased to a paint (token sheet §8.5).
    #if canImport(AppKit)
        expectRGB(Theme.palette(for: Theme.Appearance.day).tileCurrentBorder, red: 31 / 255, green: 133 / 255, blue: 82 / 255)
        expectRGB(Theme.palette(for: Theme.Appearance.night).tileCurrentBorder, red: 31 / 255, green: 133 / 255, blue: 82 / 255)
        expectRGB(Theme.sessionTileCurrentBorder, red: 31 / 255, green: 133 / 255, blue: 82 / 255)
    #endif
}

@Test func themeDangerStaysADistinctDestructiveRed() {
    #if canImport(AppKit)
        for appearance in Theme.Appearance.allCases {
            guard let danger = rgbaComponents(of: Theme.palette(for: appearance).danger) else {
                Issue.record("Could not resolve \(appearance.rawValue) danger")
                return
            }
            #expect(danger.red > 0.85, "\(appearance.rawValue) danger should read as red")
            #expect(danger.green < 0.35, "\(appearance.rawValue) danger should not drift orange or green")
            #expect(danger.blue < 0.25, "\(appearance.rawValue) danger should not drift purple")
        }
    #endif
}

// MARK: - Radius family (token sheet §6)

@Test func themeRadiusFamilyMatchesTokenSheet() {
    #expect(Theme.Radius.capsule == 999)
    #expect(Theme.Radius.soft == 30)
    #expect(Theme.Radius.focusCard == 24)
    #expect(Theme.Radius.card == 20)
    #expect(Theme.Radius.rail == 18)
    #expect(Theme.Radius.tile == 15)
    #expect(Theme.Radius.cell == 14)
    #expect(Theme.Radius.mini == 6)
    #expect(Theme.Radius.hairline == 2)
    #expect(Theme.Radius.hairlineMax == 3)
}

// MARK: - Motion & haptics (token sheet §7)

@Test func themeMotionTokensMatchTokenSheet() {
    #expect(Theme.wingEase == Theme.BezierEase(x1: 0.46, y1: -0.09, x2: 0.83, y2: 0.32))
    #expect(Theme.Motion.leafInk == 0.42)
    #expect(Theme.Motion.budOpen == 0.34)
    #expect(Theme.Motion.budOpenDelay == 0.26)
    #expect(Theme.Motion.ceremonyStem == 1.0)
    #expect(Theme.Motion.ceremonyBeat == 0.10)
    #expect(Theme.Motion.ceremonyBird == 0.35)
    #expect(Theme.Motion.holdToSkipReveal == 0.25)
    #expect(Theme.Motion.holdToSkipCommit == 0.85)
}

@Test func themeHapticTuningsMatchTokenSheet() {
    #expect(Theme.Haptics.railDetentTick == Theme.HapticTuning(intensity: 0.35, sharpness: 0.85))
    #expect(Theme.Haptics.logTap == Theme.HapticTuning(intensity: 1.0, sharpness: 0.65))
    #expect(Theme.Haptics.skipDud == Theme.HapticTuning(intensity: 0.45, sharpness: 0.15))
    #expect(Theme.Haptics.stepperTick == Theme.HapticTuning(intensity: 0.45, sharpness: 0.80))
}
