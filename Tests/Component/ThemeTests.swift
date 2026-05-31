import SwiftUI
import Testing

@testable import WorkoutTracker

#if canImport(AppKit)
    import AppKit
#endif

#if canImport(AppKit)
    private struct RGBComponents {
        let red: Double
        let green: Double
        let blue: Double
    }

    private func rgbComponents(of color: Color) -> RGBComponents? {
        NSColor(color).usingColorSpace(.deviceRGB).map {
            RGBComponents(
                red: Double($0.redComponent),
                green: Double($0.greenComponent),
                blue: Double($0.blueComponent)
            )
        }
    }

    private func expectRGB(
        _ color: Color,
        red: Double,
        green: Double,
        blue: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let rgb = rgbComponents(of: color) else {
            Issue.record("Could not resolve color to deviceRGB", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(rgb.red - red) < 0.01, "Expected red ≈ \(red), got \(rgb.red)", sourceLocation: sourceLocation)
        #expect(abs(rgb.green - green) < 0.01, "Expected green ≈ \(green), got \(rgb.green)", sourceLocation: sourceLocation)
        #expect(abs(rgb.blue - blue) < 0.01, "Expected blue ≈ \(blue), got \(rgb.blue)", sourceLocation: sourceLocation)
    }
#endif

@Test func themeGradientHasTwoStops() {
    #expect(Theme.gradientStops.count == 2)
}

@Test func themeGradientTopIsAtZero() {
    #expect(Theme.gradientStops[0].location == 0)
}

@Test func themeGradientBottomIsAtOne() {
    #expect(Theme.gradientStops[1].location == 1)
}

@Test func themeAccentIsMintGreen() {
    let accent = Theme.accent
    #if canImport(AppKit)
        guard let rgb = rgbComponents(of: accent) else {
            Issue.record("Could not resolve accent to deviceRGB")
            return
        }
        #expect(abs(rgb.red - 0.45) < 0.01, "Expected red ≈ 0.45, got \(rgb.red)")
        #expect(abs(rgb.green - 1.0) < 0.01, "Expected green ≈ 1.0, got \(rgb.green)")
        #expect(abs(rgb.blue - 0.72) < 0.01, "Expected blue ≈ 0.72, got \(rgb.blue)")
    #endif
}

@Test func themeIncludesPaletteVariantsForExploration() {
    #expect(Theme.PaletteVariant.allCases == [.dark, .black, .mintGreen, .sageLight, .blueLight])
}

@Test func themePaletteLaunchArgumentDefaultsToDark() {
    #expect(Theme.paletteVariant(from: ["WorkoutTracker"]) == .dark)
    #expect(Theme.paletteVariant(from: ["WorkoutTracker", Theme.paletteLaunchArgument]) == .dark)
    #expect(Theme.paletteVariant(from: ["WorkoutTracker", Theme.paletteLaunchArgument, "unknown"]) == .dark)
}

@Test func themePaletteLaunchArgumentSelectsRequestedVariant() {
    #expect(Theme.paletteVariant(from: ["WorkoutTracker", Theme.paletteLaunchArgument, "black"]) == .black)
    #expect(Theme.paletteVariant(from: ["WorkoutTracker", Theme.paletteLaunchArgument, "sageLight"]) == .sageLight)
    #expect(Theme.paletteVariant(from: ["WorkoutTracker", Theme.paletteLaunchArgument, "blueLight"]) == .blueLight)
}

@Test func themePaletteVariantsSetExpectedColorScheme() {
    #expect(Theme.palette(for: Theme.PaletteVariant.dark).preferredColorScheme == .dark)
    #expect(Theme.palette(for: Theme.PaletteVariant.black).preferredColorScheme == .dark)
    #expect(Theme.palette(for: Theme.PaletteVariant.mintGreen).preferredColorScheme == .dark)
    #expect(Theme.palette(for: Theme.PaletteVariant.sageLight).preferredColorScheme == .light)
    #expect(Theme.palette(for: Theme.PaletteVariant.blueLight).preferredColorScheme == .light)
}

@Test func themePaletteResolvesAppearancePreference() {
    #expect(Theme.palette(for: AppearancePreference.light).preferredColorScheme == .light)
    #expect(Theme.palette(for: AppearancePreference.dark).preferredColorScheme == .dark)
    #expect(Theme.palette(for: AppearancePreference.system).preferredColorScheme == .dark)
}

@Test func themePalettesUseApprovedDarkAndSageLightColors() {
    #if canImport(AppKit)
        let dark = Theme.palette(for: Theme.PaletteVariant.dark)
        #expect(dark.gradientStops.count == 2)
        expectRGB(dark.gradientStops[0].color, red: 0.02, green: 0.03, blue: 0.025)
        expectRGB(dark.gradientStops[1].color, red: 0.015, green: 0.11, blue: 0.065)
        expectRGB(dark.accent, red: 0.45, green: 1.0, blue: 0.72)
        expectRGB(dark.activeCardStroke, red: 0.23, green: 0.82, blue: 0.48)
        expectRGB(dark.sessionTileComplete, red: 0.03, green: 0.32, blue: 0.16)

        let sageLight = Theme.palette(for: Theme.PaletteVariant.sageLight)
        #expect(sageLight.gradientStops.count == 2)
        expectRGB(sageLight.gradientStops[0].color, red: 0.91, green: 0.93, blue: 0.86)
        expectRGB(sageLight.gradientStops[1].color, red: 0.78, green: 0.88, blue: 0.75)
        expectRGB(sageLight.accent, red: 0.05, green: 0.42, blue: 0.25)
        expectRGB(sageLight.activeCardStroke, red: 0.12, green: 0.52, blue: 0.32)
        expectRGB(sageLight.sessionTileComplete, red: 0.06, green: 0.38, blue: 0.22)
    #endif
}

@Test func themeGradientHasNoOrangeTones() {
    #if canImport(AppKit)
        for variant in Theme.PaletteVariant.allCases {
            for stop in Theme.palette(for: variant).gradientStops {
                guard let rgb = rgbComponents(of: stop.color) else { continue }
                // Orange: high red AND red significantly dominates green.
                #expect(
                    !(rgb.red > 0.3 && rgb.red > 1.5 * rgb.green),
                    "\(variant.rawValue) stop at \(stop.location) is orange: r=\(rgb.red) g=\(rgb.green)"
                )
            }
        }
    #endif
}

@Test func themeGradientMovesToDarkBlackGreenDirection() {
    #if canImport(AppKit)
        for stop in Theme.gradientStops {
            guard let rgb = rgbComponents(of: stop.color) else { continue }
            #expect(rgb.red < 0.12, "Stop at \(stop.location): red \(rgb.red) too high for dark green")
            #expect(rgb.green < 0.18, "Stop at \(stop.location): green \(rgb.green) too high for dark green")
            #expect(rgb.blue < 0.12, "Stop at \(stop.location): blue \(rgb.blue) too high for dark green")
        }

        guard let bottom = rgbComponents(of: Theme.gradientStops[1].color) else {
            Issue.record("Could not resolve bottom gradient stop to deviceRGB")
            return
        }
        #expect(bottom.green > bottom.red + 0.03, "Expected bottom stop to lean green")
        #expect(bottom.green > bottom.blue + 0.02, "Expected bottom stop to lean green")
    #endif
}

@Test func themePaletteVariantsKeepActionAccentReadableAndPurposeful() {
    #if canImport(AppKit)
        for variant in Theme.PaletteVariant.allCases {
            let palette = Theme.palette(for: variant)
            guard let accent = rgbComponents(of: palette.accent) else {
                Issue.record("Could not resolve \(variant.rawValue) accent")
                return
            }

            switch variant {
            case .dark, .black, .mintGreen, .sageLight:
                #expect(accent.green > accent.red + 0.15, "\(variant.rawValue) accent should lean green")
            case .blueLight:
                #expect(accent.blue > accent.red + 0.35, "blueLight accent should lean blue")
                #expect(accent.blue > accent.green + 0.20, "blueLight accent should lean blue")
            }
        }
    #endif
}

@Test func themeSageLightPaletteUsesSoftSageCreamWithoutAmber() {
    #if canImport(AppKit)
        for stop in Theme.palette(for: Theme.PaletteVariant.sageLight).gradientStops {
            guard let rgb = rgbComponents(of: stop.color) else { continue }
            #expect(rgb.red > 0.70)
            #expect(rgb.green > 0.78)
            #expect(rgb.blue > 0.70)
            #expect(rgb.green >= rgb.red, "Sage cream should stay green-led, not amber")
            #expect(rgb.red > rgb.blue, "Sage cream should be softer than a cool white")
            #expect(rgb.red < rgb.blue + 0.08, "Sage cream should not become beige")
            #expect(max(rgb.red, rgb.green, rgb.blue) <= 0.94, "Sage cream should be less bright than white")
        }
    #endif
}

@Test func themeBlueLightPaletteUsesCoolLightBackground() {
    #if canImport(AppKit)
        for stop in Theme.palette(for: Theme.PaletteVariant.blueLight).gradientStops {
            guard let rgb = rgbComponents(of: stop.color) else { continue }
            #expect(rgb.red > 0.70)
            #expect(rgb.green > 0.78)
            #expect(rgb.blue > 0.78)
            #expect(rgb.blue >= rgb.red, "Blue Light should stay cool")
        }
    #endif
}

@Test func themeSessionProgressTrackIsDarkBehindMintFill() {
    #if canImport(AppKit)
        guard let rgb = rgbComponents(of: Theme.progressTrack) else {
            Issue.record("Could not resolve progress track to deviceRGB")
            return
        }
        #expect(rgb.red < 0.08)
        #expect(rgb.green < 0.12)
        #expect(rgb.blue < 0.10)
        #expect(rgb.green >= rgb.red)
    #endif
}

@Test func themeActiveCardSurfaceUsesGreenFillAndStroke() {
    #if canImport(AppKit)
        guard let fill = rgbComponents(of: Theme.activeCardFill) else {
            Issue.record("Could not resolve active card fill to deviceRGB")
            return
        }
        guard let stroke = rgbComponents(of: Theme.activeCardStroke) else {
            Issue.record("Could not resolve active card stroke to deviceRGB")
            return
        }

        #expect(fill.green > fill.red + 0.10)
        #expect(fill.green > fill.blue + 0.05)
        #expect(stroke.green > stroke.red + 0.30)
        #expect(stroke.green > stroke.blue + 0.20)
    #endif
}

@Test func themeLastPerformedCardSurfaceIsSubtleDeepGreen() {
    #if canImport(AppKit)
        guard let fill = rgbComponents(of: Theme.lastPerformedCardFill) else {
            Issue.record("Could not resolve Last Performed card fill to deviceRGB")
            return
        }
        guard let stroke = rgbComponents(of: Theme.lastPerformedCardStroke) else {
            Issue.record("Could not resolve Last Performed card stroke to deviceRGB")
            return
        }

        #expect(fill.green > fill.red + 0.04)
        #expect(fill.green > fill.blue + 0.02)
        #expect(fill.green < 0.18)
        #expect(stroke.green > stroke.red + 0.18)
        #expect(stroke.green > stroke.blue + 0.10)
    #endif
}

@Test func themeCardCornerRadiusIs16() {
    #expect(Theme.cardCornerRadius == 16)
}

@Test func themeCardSpacingExists() {
    #expect(Theme.cardSpacing > 0)
}

@Test func themeIncludesSmartValuePillAndRPEGridConstants() {
    #expect(Theme.pillMinHeight == 86)
    #expect(Theme.weightIncrementThreshold == 100)
    #expect(Theme.lightWeightIncrementOptions == [2.5, 5])
    #expect(Theme.heavyWeightIncrementOptions == [5, 10])
    #expect(Theme.rpeGridCellHeight == 48)
}

@Test func themeIncludesSessionTileConstants() {
    #expect(Theme.sessionTileCornerRadius == 8)
    #expect(Theme.sessionTileMinHeight == 86)
    #expect(Theme.sessionTileSpacing == 10)

    #if canImport(AppKit)
        #expect(rgbComponents(of: Theme.sessionTileComplete) != nil)
        #expect(rgbComponents(of: Theme.sessionTileIncomplete) != nil)
        #expect(rgbComponents(of: Theme.sessionTileCurrentBorder) != nil)
    #endif
}

@Test func themeIncludesActiveSetTransitionTimingConstants() {
    #expect(Theme.logButtonCheckmarkDuration == 0.2)
    #expect(Theme.holdToSkipDuration == 0.8)
    #expect(Theme.holdToSkipRevealDelay == 0.25)
    #expect(Theme.holdToSkipTapMaximumDuration < Theme.holdToSkipDuration)
    #expect(Theme.holdToSkipRevealDelay < Theme.holdToSkipDuration)
    #expect(Theme.momentumFlowTotalDuration == 0.65)
    #expect(Theme.momentumDropDuration == 0.4)
    #expect(Theme.momentumRiseDuration == 0.5)
    #expect(Theme.momentumRiseDelay < Theme.momentumDropDuration)
    #expect(Theme.skipFadeUpDuration == 0.45)
    #expect(Theme.exerciseCompletionBeatDuration == 0.2)
    #expect(Theme.focusMorphDuration == 0.28)
    #expect(Theme.momentumSpringStiffness > 0)
    #expect(Theme.momentumSpringDamping > 0)
}
