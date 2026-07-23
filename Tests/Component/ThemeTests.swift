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

    /// Asserts a color is sage-led rather than neutral black or a foreign hue — the pigment
    /// heart of the Room Re-lights Rule (DESIGN.md §2). Green must lead red and blue, and the
    /// channel spread must clear a floor so a re-lit surface can never collapse to gray/black.
    private func expectSageLed(
        _ color: Color,
        floor: Double = 0.012,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let rgb = rgbaComponents(of: color) else {
            Issue.record("Could not resolve color to deviceRGB", sourceLocation: sourceLocation)
            return
        }
        #expect(rgb.green >= rgb.red, "sage-led: green (\(rgb.green)) should lead red (\(rgb.red))", sourceLocation: sourceLocation)
        #expect(rgb.green > rgb.blue, "sage-led: green (\(rgb.green)) should lead blue (\(rgb.blue))", sourceLocation: sourceLocation)
        #expect(
            rgb.green - min(rgb.red, rgb.blue) >= floor,
            "not neutral: a channel spread ≥ \(floor) proves a preserved sage hue, not gray/black",
            sourceLocation: sourceLocation
        )
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

@Test func themeBudGlowIsTheNightOnlyPageGlow() throws {
    // The active bud carries the page's one glow at Night; Day leaves it unlit (token sheet §Stage & branch).
    #expect(Theme.palette(for: Theme.Appearance.day).budGlow == nil)
    #if canImport(AppKit)
        let nightGlow = try #require(Theme.palette(for: Theme.Appearance.night).budGlow)
        expectRGB(nightGlow, red: 120 / 255, green: 240 / 255, blue: 178 / 255, alpha: 0.32)
    #endif
}

@Test func themeSupersetPartnerBranchQuietsByPigmentByDayAndTranslucencyAtNight() throws {
    // The forked stem's partner subordinates by foliage pigment by Day and by
    // that same foliage @ 0.55 at Night (DESIGN.md §5.4).
    #if canImport(AppKit)
        expectRGB(
            Theme.palette(for: Theme.Appearance.day).supersetPartnerBranch,
            red: 87 / 255,
            green: 145 / 255,
            blue: 104 / 255
        )
        expectRGB(
            Theme.palette(for: Theme.Appearance.night).supersetPartnerBranch,
            red: 87 / 255,
            green: 145 / 255,
            blue: 104 / 255,
            alpha: 0.55
        )
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
    #expect(Theme.Motion.holdToSkipLoggedCommit == 0.9)
    #expect(Theme.Motion.holdToSkipSkippedCommit == 1.1)
}

@Test func themeHapticTuningsMatchTokenSheet() {
    #expect(Theme.Haptics.railDetentTick == Theme.HapticTuning(intensity: 0.35, sharpness: 0.85))
    #expect(Theme.Haptics.logTap == Theme.HapticTuning(intensity: 1.0, sharpness: 0.65))
    #expect(Theme.Haptics.skipDud == Theme.HapticTuning(intensity: 0.45, sharpness: 0.15))
    #expect(Theme.Haptics.stepperTick == Theme.HapticTuning(intensity: 0.45, sharpness: 0.80))
}

// MARK: - Night validation of the two flagged surfaces (PRD #458 slice 8, ADR-0007)
//
// The Exercise History sheet and the Block grid were the two surfaces never re-prototyped at
// night; the map required them validated against the Room Re-lights Rule before their baselines
// lock (DESIGN.md §2: "Night is the same room re-lit, never recolored: hue-preserved deep sage
// paper, foliage pigment for everything that grows, cream kept as the light source. No neutral
// black, no new hues at night."). These assertions are the programmatic half of that sign-off —
// the deterministic Visual Baselines are the pixel half.

@Test func nightExerciseHistorySheetObeysTheRoomRelightsRule() {
    #if canImport(AppKit)
        let night = Theme.palette(for: Theme.Appearance.night)

        // The night sheet paper is deep sage, never neutral black (#418 recipe, flagged surface).
        expectSageLed(night.sheetFill)
        if let sheet = rgbaComponents(of: night.sheetFill) {
            #expect(sheet.green < 0.2, "the night sheet stays a deep sage paper, not a mid-tone")
        }

        // Cream stays the light source: carved chips and the grabber are cream at low opacity.
        for creamSurface in [night.chipCarvedFill, night.grabber] {
            expectSageLed(creamSurface)
            if let cream = rgbaComponents(of: creamSurface) {
                #expect(cream.green > 0.85, "cream is kept as the light source, sage-led and bright")
            }
        }
    #endif
}

@Test func nightBlockGridObeysTheRoomRelightsRule() {
    #if canImport(AppKit)
        let night = Theme.palette(for: Theme.Appearance.night)

        // Everything that grows takes foliage pigment: the complete tile fills in foliage green.
        expectSageLed(night.sessionTileComplete)
        if let foliage = rgbaComponents(of: night.sessionTileComplete) {
            #expect(foliage.green > 0.4 && foliage.green < 0.75, "the complete tile is mid foliage, not ink or cream")
        }

        // The quiet strokes and shades stay sage-led — no neutral gray tiles at night.
        expectSageLed(night.tileGhostStroke)
        for creamSurface in [night.tileCurrentFill, night.weekCardShade] {
            expectSageLed(creamSurface)
            if let cream = rgbaComponents(of: creamSurface) {
                #expect(cream.green > 0.85, "cream is kept as the light source, sage-led and bright")
            }
        }

        // The current tile's rim is the approved literal in both appearances — never re-lit away.
        expectRGB(night.tileCurrentBorder, red: 31 / 255, green: 133 / 255, blue: 82 / 255)
    #endif
}

@Test func nightPreservesTheRoomsSageHueAcrossAppearances() {
    // The room re-lights, it does not recolor: the sheet paper and the page paper stay sage-led in
    // both appearances, only their lightness changes.
    #if canImport(AppKit)
        for appearance in Theme.Appearance.allCases {
            let palette = Theme.palette(for: appearance)
            expectSageLed(palette.sheetFill)
            expectSageLed(palette.paper.baseTop)
            expectSageLed(palette.paper.baseBottom)
        }
    #endif
}

// MARK: - Input-block roles (token sheet §Active Set Card; ledger §1.1 — the two fixed alias wrongs)

@Test func themePillFillIsCreamNotTheSurfaceAlias() {
    // The first pass mapped `pillFill → surface` (cream @ 52%); the token sheet says the stepper
    // buttons are cream @ 85% by Day, cream @ 6% at Night (ledger §1.1).
    #if canImport(AppKit)
        expectRGB(
            Theme.palette(for: Theme.Appearance.day).pillFill,
            red: 242 / 255, green: 247 / 255, blue: 232 / 255, alpha: 0.85
        )
        expectRGB(
            Theme.palette(for: Theme.Appearance.night).pillFill,
            red: 242 / 255, green: 247 / 255, blue: 232 / 255, alpha: 0.06
        )
    #endif
}

@Test func themePillStrokeIsItsOwnHairlineNotTheQueueStroke() {
    // The first pass mapped `pillStroke → queueStroke` (0.38 / cream @ 20%); the token sheet says
    // rgba(82,111,90,0.34) by Day and cream @ 16% at Night (ledger §1.1).
    #if canImport(AppKit)
        expectRGB(
            Theme.palette(for: Theme.Appearance.day).pillStroke,
            red: 82 / 255, green: 111 / 255, blue: 90 / 255, alpha: 0.34
        )
        expectRGB(
            Theme.palette(for: Theme.Appearance.night).pillStroke,
            red: 242 / 255, green: 247 / 255, blue: 232 / 255, alpha: 0.16
        )
    #endif
}

@Test func themePillFillIsDistinctFromSurfaceAndQueueStroke() {
    // A regression guard on the fix: the roles must no longer be equal to what they were aliased to.
    let day = Theme.palette(for: Theme.Appearance.day)
    #if canImport(AppKit)
        let pillFill = rgbaComponents(of: day.pillFill)
        let surface = rgbaComponents(of: day.surface)
        #expect(pillFill?.alpha != surface?.alpha, "pillFill must not still resolve to the surface alias")
    #endif
}

// MARK: - Elevation & light kit (token sheet §3 / §5.5 / §5.6; ledger §1.2 — the absent tokens)

@Test func themeSurfaceShadowIsADayDoubleDropAndANightInsetBorder() {
    #if canImport(AppKit)
        let day = Theme.palette(for: Theme.Appearance.day).surfaceShadow
        #expect(day.count == 2)
        #expect(day[0] == Theme.BoxShadow(y: 1, blur: 2, color: Theme.rgb(21, 33, 24, 0.04)))
        #expect(day[1] == Theme.BoxShadow(y: 14, blur: 30, color: Theme.rgb(21, 33, 24, 0.07)))

        let night = Theme.palette(for: Theme.Appearance.night).surfaceShadow
        #expect(night.count == 1)
        #expect(night[0].isInset, "the night surface elevation is a border-as-light inset, not a drop")
        #expect(night[0].spread == 1)
        expectRGB(night[0].color, red: 242 / 255, green: 247 / 255, blue: 232 / 255, alpha: 0.10)
    #endif
}

@Test func themeLogShadowIsADayGreenDropAndANightGreenGlow() {
    #if canImport(AppKit)
        let day = Theme.palette(for: Theme.Appearance.day).logShadow
        #expect(day.count == 2)
        #expect(day[0] == Theme.BoxShadow(y: 1, blur: 2, color: Theme.rgb(13, 46, 28, 0.22)))
        #expect(day[1] == Theme.BoxShadow(y: 10, blur: 22, color: Theme.rgb(13, 60, 35, 0.16)))

        let night = Theme.palette(for: Theme.Appearance.night).logShadow
        #expect(night.count == 1)
        #expect(night[0].yOffset == 0 && night[0].blur == 22, "the night Log elevation is a glow, no drop")
        expectRGB(night[0].color, red: 31 / 255, green: 133 / 255, blue: 82 / 255, alpha: 0.35)
    #endif
}

@Test func themeSkipFillOverlayIsMutedInBothAppearances() {
    // Token sheet §Log capsule: the hold-to-skip overlay is muted @ 30% — never danger red
    // (ledger §2.8). The night recipe lands with this input-block build slice (#488).
    #if canImport(AppKit)
        expectRGB(
            try! #require(Theme.palette(for: Theme.Appearance.day).skipFillOverlay),
            red: 82 / 255, green: 100 / 255, blue: 87 / 255, alpha: 0.30
        )
        expectRGB(
            try! #require(Theme.palette(for: Theme.Appearance.night).skipFillOverlay),
            red: 154 / 255, green: 170 / 255, blue: 155 / 255, alpha: 0.30
        )
    #endif
}

@Test func themePressedFillIsADayValueDeferredAtNight() {
    // The pressed / logged Log-capsule fill (#0A5936) is a day value; its night recipe is still
    // flagged "— (build)" and has no consumer yet, so it stays deferred.
    #if canImport(AppKit)
        expectRGB(try! #require(Theme.palette(for: Theme.Appearance.day).pressedFill), red: 10 / 255, green: 89 / 255, blue: 54 / 255)
    #endif
    #expect(Theme.palette(for: Theme.Appearance.night).pressedFill == nil)
}

@Test func themeRailSelectedFillIsALitCreamChipInBothAppearances() {
    // The selected rail chip takes a cream fill under the inset action ring (token sheet §Active
    // Set Card, "rail chip selected"); the ring is the primary selection signal at Night.
    #if canImport(AppKit)
        expectRGB(
            Theme.palette(for: Theme.Appearance.day).railSelectedFill,
            red: 242 / 255, green: 247 / 255, blue: 232 / 255, alpha: 0.95
        )
        expectRGB(
            Theme.palette(for: Theme.Appearance.night).railSelectedFill,
            red: 242 / 255, green: 247 / 255, blue: 232 / 255, alpha: 0.14
        )
    #endif
}

@Test func themeLightKitCardLowAndSunGlowMatchTokenSheet() {
    #if canImport(AppKit)
        #expect(Theme.LightKit.cardLow == [
            Theme.BoxShadow(y: 1, blur: 2, color: Theme.Paint.ink.opacity(0.06)),
            Theme.BoxShadow(y: 3, blur: 8, color: Theme.Paint.ink.opacity(0.07)),
        ])
        #expect(Theme.LightKit.sunGlow == [
            Theme.BoxShadow(y: 0, blur: 0, spread: 4, color: Theme.rgb(242, 247, 232, 0.45)),
            Theme.BoxShadow(y: 2, blur: 18, color: Theme.rgb(220, 235, 190, 0.9)),
        ])
    #endif
}

@Test func themeLightKitFocusCardIsMorningLightWithACreamGlowRim() {
    #if canImport(AppKit)
        expectRGB(Theme.LightKit.focusCardFill, red: 248 / 255, green: 251 / 255, blue: 238 / 255, alpha: 0.96)
        // The rim is cardLow under a cream 5px halo and a soft sun bloom.
        let rim = Theme.LightKit.focusCardGlowRim
        #expect(rim.count == 4)
        #expect(rim[2] == Theme.BoxShadow(y: 0, blur: 0, spread: 5, color: Theme.rgb(250, 252, 238, 0.5)))
        #expect(rim[3] == Theme.BoxShadow(y: 6, blur: 30, color: Theme.rgb(228, 240, 200, 0.95)))
    #endif
}

@Test func themeLightKitWashesAndDotsMatchTokenSheet() {
    #if canImport(AppKit)
        // The page sunbeam is a three-stop radial; the tile top-light a two-stop sheen.
        #expect(Theme.LightKit.pageSunbeam.stops.count == 3)
        #expect(Theme.LightKit.pageSunbeam.center == UnitPoint(x: 0.82, y: -0.08))
        #expect(Theme.LightKit.tileTopLight.stops.count == 2)
        #expect(Theme.LightKit.tileTopLight.center == UnitPoint(x: 0.78, y: -0.30))

        // The volume control raises on cream @ 90%; its pressed state is the carved-chip recipe.
        expectRGB(Theme.LightKit.volumeControlRaisedFill, red: 242 / 255, green: 247 / 255, blue: 232 / 255, alpha: 0.90)

        // Data dot: solid ink r4.5 with a paper core. Approx dot: hollow ink outline r4 @ 1.5.
        #expect(Theme.LightKit.dataDot == Theme.DotSpec(color: Theme.Paint.ink, radius: 4.5, lineWidth: 0, hasPaperCore: true))
        #expect(Theme.LightKit.approxDot == Theme.DotSpec(color: Theme.Paint.ink, radius: 4, lineWidth: 1.5, hasPaperCore: false))
    #endif
}
