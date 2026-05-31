import Foundation
import SwiftUI

enum Theme {
    enum PaletteVariant: String, CaseIterable {
        case dark
        case black
        case mintGreen
        case sageLight
        case blueLight
    }

    struct Palette {
        let preferredColorScheme: ColorScheme
        let gradientStops: [Gradient.Stop]
        let accent: Color
        let accentDarkText: Color
        let progressTrack: Color
        let activeCardFill: Color
        let activeCardStroke: Color
        let lastPerformedCardFill: Color
        let lastPerformedCardStroke: Color
        let pillFill: Color
        let pillStroke: Color
        let sessionTileComplete: Color
        let sessionTileIncomplete: Color
        let sessionTileUnavailable: Color
        let valueText: Color
        let badgeFill: Color
        let bannerFill: Color
        let bannerStroke: Color
        let sessionTileCompleteText: Color
        let sessionTileIncompleteText: Color
        let sessionTileUnavailableText: Color
        let sessionTileRestingBorder: Color
    }

    static let paletteLaunchArgument = "-WORKOUT_THEME"

    static let activePaletteVariant = paletteVariant(from: ProcessInfo.processInfo.arguments)
    static let activePalette = palette(for: activePaletteVariant)

    static let preferredColorScheme = activePalette.preferredColorScheme
    static let gradientStops = activePalette.gradientStops

    static let gradient = LinearGradient(
        stops: gradientStops,
        startPoint: .top,
        endPoint: .bottom
    )

    static let accent = activePalette.accent
    static let accentDarkText = activePalette.accentDarkText
    static let progressTrack = activePalette.progressTrack
    static let activeCardFill = activePalette.activeCardFill
    static let activeCardStroke = activePalette.activeCardStroke
    static let lastPerformedCardFill = activePalette.lastPerformedCardFill
    static let lastPerformedCardStroke = activePalette.lastPerformedCardStroke
    static let pillFill = activePalette.pillFill
    static let pillStroke = activePalette.pillStroke
    static let sessionTileComplete = activePalette.sessionTileComplete
    static let sessionTileIncomplete = activePalette.sessionTileIncomplete
    static let sessionTileUnavailable = activePalette.sessionTileUnavailable
    static let sessionTileCurrentBorder = accent
    static let valueText = activePalette.valueText
    static let badgeFill = activePalette.badgeFill
    static let bannerFill = activePalette.bannerFill
    static let bannerStroke = activePalette.bannerStroke
    static let sessionTileCompleteText = activePalette.sessionTileCompleteText
    static let sessionTileIncompleteText = activePalette.sessionTileIncompleteText
    static let sessionTileUnavailableText = activePalette.sessionTileUnavailableText
    static let sessionTileRestingBorder = activePalette.sessionTileRestingBorder

    static let cardCornerRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 16
    static let sessionTileCornerRadius: CGFloat = 8
    static let sessionTileMinHeight: CGFloat = 86
    static let sessionTileSpacing: CGFloat = 10
    static let sessionTileCurrentBorderWidth: CGFloat = 1.5
    static let sessionTileUnavailableOpacity = 0.55
    static let pillCornerRadius: CGFloat = 8
    static let pillMinHeight: CGFloat = 86
    static let pillSpacing: CGFloat = 10
    static let rpeGridSpacing: CGFloat = 8
    static let rpeGridCellHeight: CGFloat = 48
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

    static func paletteVariant(from arguments: [String]) -> PaletteVariant {
        guard
            let argumentIndex = arguments.firstIndex(of: paletteLaunchArgument),
            arguments.indices.contains(arguments.index(after: argumentIndex)),
            let variant = PaletteVariant(rawValue: arguments[arguments.index(after: argumentIndex)])
        else {
            return .dark
        }
        return variant
    }

    static func palette(for variant: PaletteVariant) -> Palette {
        switch variant {
        case .dark:
            darkPalette
        case .black:
            blackPalette
        case .mintGreen:
            mintGreenPalette
        case .sageLight:
            sageLightPalette
        case .blueLight:
            blueLightPalette
        }
    }

    private static let darkPalette = Palette(
        preferredColorScheme: .dark,
        gradientStops: [
            .init(color: Color(red: 0.02, green: 0.03, blue: 0.025), location: 0),
            .init(color: Color(red: 0.015, green: 0.11, blue: 0.065), location: 1)
        ],
        accent: Color(red: 0.45, green: 1.0, blue: 0.72),
        accentDarkText: Color(red: 0.02, green: 0.12, blue: 0.07),
        progressTrack: Color(red: 0.025, green: 0.055, blue: 0.04),
        activeCardFill: Color(red: 0.03, green: 0.20, blue: 0.12).opacity(0.72),
        activeCardStroke: Color(red: 0.23, green: 0.82, blue: 0.48),
        lastPerformedCardFill: Color(red: 0.03, green: 0.10, blue: 0.07).opacity(0.82),
        lastPerformedCardStroke: Color(red: 0.13, green: 0.36, blue: 0.25),
        pillFill: Color(red: 0.03, green: 0.06, blue: 0.05).opacity(0.88),
        pillStroke: Color(red: 0.24, green: 0.68, blue: 0.42).opacity(0.75),
        sessionTileComplete: Color(red: 0.03, green: 0.32, blue: 0.16),
        sessionTileIncomplete: Color(red: 0.025, green: 0.055, blue: 0.045).opacity(0.24),
        sessionTileUnavailable: Color(red: 0.025, green: 0.055, blue: 0.045).opacity(0.12),
        valueText: .white,
        badgeFill: .white.opacity(0.12),
        bannerFill: .white.opacity(0.14),
        bannerStroke: .white.opacity(0.10),
        sessionTileCompleteText: .white,
        sessionTileIncompleteText: .white.opacity(0.64),
        sessionTileUnavailableText: .white.opacity(0.4),
        sessionTileRestingBorder: .white.opacity(0.10)
    )

    private static let blackPalette = Palette(
        preferredColorScheme: .dark,
        gradientStops: [
            .init(color: Color(red: 0.0, green: 0.008, blue: 0.004), location: 0),
            .init(color: Color(red: 0.0, green: 0.025, blue: 0.016), location: 1)
        ],
        accent: Color(red: 0.40, green: 0.96, blue: 0.66),
        accentDarkText: Color(red: 0.0, green: 0.08, blue: 0.045),
        progressTrack: Color(red: 0.008, green: 0.02, blue: 0.014),
        activeCardFill: Color(red: 0.008, green: 0.07, blue: 0.04).opacity(0.9),
        activeCardStroke: Color(red: 0.14, green: 0.66, blue: 0.36),
        lastPerformedCardFill: Color(red: 0.006, green: 0.04, blue: 0.026).opacity(0.88),
        lastPerformedCardStroke: Color(red: 0.10, green: 0.32, blue: 0.22),
        pillFill: Color(red: 0.006, green: 0.018, blue: 0.014).opacity(0.94),
        pillStroke: Color(red: 0.16, green: 0.50, blue: 0.30).opacity(0.75),
        sessionTileComplete: Color(red: 0.016, green: 0.22, blue: 0.11),
        sessionTileIncomplete: Color(red: 0.008, green: 0.02, blue: 0.014).opacity(0.28),
        sessionTileUnavailable: Color(red: 0.008, green: 0.02, blue: 0.014).opacity(0.14),
        valueText: .white,
        badgeFill: .white.opacity(0.10),
        bannerFill: .white.opacity(0.12),
        bannerStroke: .white.opacity(0.10),
        sessionTileCompleteText: .white,
        sessionTileIncompleteText: .white.opacity(0.62),
        sessionTileUnavailableText: .white.opacity(0.36),
        sessionTileRestingBorder: .white.opacity(0.09)
    )

    private static let mintGreenPalette = Palette(
        preferredColorScheme: .dark,
        gradientStops: [
            .init(color: Color(red: 0.015, green: 0.075, blue: 0.047), location: 0),
            .init(color: Color(red: 0.027, green: 0.23, blue: 0.145), location: 1)
        ],
        accent: Color(red: 0.52, green: 1.0, blue: 0.78),
        accentDarkText: Color(red: 0.01, green: 0.13, blue: 0.08),
        progressTrack: Color(red: 0.026, green: 0.085, blue: 0.055),
        activeCardFill: Color(red: 0.045, green: 0.25, blue: 0.16).opacity(0.74),
        activeCardStroke: Color(red: 0.33, green: 0.89, blue: 0.58),
        lastPerformedCardFill: Color(red: 0.035, green: 0.16, blue: 0.105).opacity(0.82),
        lastPerformedCardStroke: Color(red: 0.18, green: 0.50, blue: 0.34),
        pillFill: Color(red: 0.028, green: 0.09, blue: 0.064).opacity(0.9),
        pillStroke: Color(red: 0.28, green: 0.72, blue: 0.45).opacity(0.78),
        sessionTileComplete: Color(red: 0.035, green: 0.36, blue: 0.18),
        sessionTileIncomplete: Color(red: 0.026, green: 0.085, blue: 0.055).opacity(0.28),
        sessionTileUnavailable: Color(red: 0.026, green: 0.085, blue: 0.055).opacity(0.14),
        valueText: .white,
        badgeFill: .white.opacity(0.12),
        bannerFill: .white.opacity(0.14),
        bannerStroke: .white.opacity(0.10),
        sessionTileCompleteText: .white,
        sessionTileIncompleteText: .white.opacity(0.68),
        sessionTileUnavailableText: .white.opacity(0.42),
        sessionTileRestingBorder: .white.opacity(0.11)
    )

    private static let sageLightPalette = Palette(
        preferredColorScheme: .light,
        gradientStops: [
            .init(color: Color(red: 0.91, green: 0.93, blue: 0.86), location: 0),
            .init(color: Color(red: 0.78, green: 0.88, blue: 0.75), location: 1)
        ],
        accent: Color(red: 0.05, green: 0.42, blue: 0.25),
        accentDarkText: Color(red: 0.95, green: 0.97, blue: 0.91),
        progressTrack: Color(red: 0.70, green: 0.78, blue: 0.68),
        activeCardFill: Color(red: 0.88, green: 0.93, blue: 0.84).opacity(0.96),
        activeCardStroke: Color(red: 0.12, green: 0.52, blue: 0.32),
        lastPerformedCardFill: Color(red: 0.82, green: 0.89, blue: 0.80).opacity(0.94),
        lastPerformedCardStroke: Color(red: 0.32, green: 0.55, blue: 0.40),
        pillFill: Color(red: 0.95, green: 0.965, blue: 0.91).opacity(0.96),
        pillStroke: Color(red: 0.46, green: 0.66, blue: 0.53).opacity(0.78),
        sessionTileComplete: Color(red: 0.06, green: 0.38, blue: 0.22),
        sessionTileIncomplete: Color(red: 0.91, green: 0.94, blue: 0.87).opacity(0.9),
        sessionTileUnavailable: Color(red: 0.82, green: 0.87, blue: 0.78).opacity(0.7),
        valueText: .primary,
        badgeFill: .black.opacity(0.07),
        bannerFill: .black.opacity(0.07),
        bannerStroke: .black.opacity(0.10),
        sessionTileCompleteText: .white,
        sessionTileIncompleteText: .primary.opacity(0.70),
        sessionTileUnavailableText: .secondary.opacity(0.86),
        sessionTileRestingBorder: .black.opacity(0.10)
    )

    private static let blueLightPalette = Palette(
        preferredColorScheme: .light,
        gradientStops: [
            .init(color: Color(red: 0.94, green: 0.97, blue: 0.995), location: 0),
            .init(color: Color(red: 0.82, green: 0.90, blue: 0.98), location: 1)
        ],
        accent: Color(red: 0.08, green: 0.30, blue: 0.78),
        accentDarkText: .white,
        progressTrack: Color(red: 0.75, green: 0.82, blue: 0.92),
        activeCardFill: Color(red: 0.90, green: 0.95, blue: 1.0).opacity(0.96),
        activeCardStroke: Color(red: 0.16, green: 0.39, blue: 0.84),
        lastPerformedCardFill: Color(red: 0.88, green: 0.92, blue: 0.98).opacity(0.94),
        lastPerformedCardStroke: Color(red: 0.36, green: 0.49, blue: 0.72),
        pillFill: Color(red: 0.98, green: 0.99, blue: 1.0).opacity(0.96),
        pillStroke: Color(red: 0.45, green: 0.56, blue: 0.76).opacity(0.78),
        sessionTileComplete: Color(red: 0.08, green: 0.27, blue: 0.64),
        sessionTileIncomplete: Color(red: 0.95, green: 0.97, blue: 1.0).opacity(0.9),
        sessionTileUnavailable: Color(red: 0.86, green: 0.90, blue: 0.96).opacity(0.72),
        valueText: .primary,
        badgeFill: .black.opacity(0.07),
        bannerFill: .black.opacity(0.07),
        bannerStroke: .black.opacity(0.10),
        sessionTileCompleteText: .white,
        sessionTileIncompleteText: .primary.opacity(0.70),
        sessionTileUnavailableText: .secondary.opacity(0.86),
        sessionTileRestingBorder: .black.opacity(0.10)
    )
}
