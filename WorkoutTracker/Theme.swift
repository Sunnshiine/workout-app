import SwiftUI

enum Theme {
    static let gradientStops: [Gradient.Stop] = [
        .init(color: Color(red: 0.02, green: 0.03, blue: 0.025), location: 0),
        .init(color: Color(red: 0.015, green: 0.11, blue: 0.065), location: 1)
    ]

    static let gradient = LinearGradient(
        stops: gradientStops,
        startPoint: .top,
        endPoint: .bottom
    )

    static let accent = Color(red: 0.45, green: 1.0, blue: 0.72)
    static let accentDarkText = Color(red: 0.02, green: 0.12, blue: 0.07)
    static let progressTrack = Color(red: 0.025, green: 0.055, blue: 0.04)
    static let activeCardFill = Color(red: 0.03, green: 0.20, blue: 0.12).opacity(0.72)
    static let activeCardStroke = Color(red: 0.23, green: 0.82, blue: 0.48)
    static let lastPerformedCardFill = Color(red: 0.03, green: 0.10, blue: 0.07).opacity(0.82)
    static let lastPerformedCardStroke = Color(red: 0.13, green: 0.36, blue: 0.25)
    static let pillFill = Color(red: 0.03, green: 0.06, blue: 0.05).opacity(0.88)
    static let pillStroke = Color(red: 0.24, green: 0.68, blue: 0.42).opacity(0.75)
    static let sessionTileComplete = Color(red: 0.03, green: 0.32, blue: 0.16)
    static let sessionTileHasOpenExercises = Color(red: 0.86, green: 0.58, blue: 0.16)
    static let sessionTileCurrent = accent
    static let sessionTileUpcoming = Color(red: 0.025, green: 0.055, blue: 0.045)

    static let cardCornerRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 16
    static let sessionTileCornerRadius: CGFloat = 8
    static let sessionTileMinHeight: CGFloat = 86
    static let sessionTileSpacing: CGFloat = 10
    static let pillCornerRadius: CGFloat = 8
    static let pillMinHeight: CGFloat = 86
    static let pillSpacing: CGFloat = 10
    static let rpeGridSpacing: CGFloat = 8
    static let rpeGridCellHeight: CGFloat = 48
    static let weightIncrementThreshold = 100.0
    static let lightWeightIncrementOptions = [2.5, 5.0]
    static let heavyWeightIncrementOptions = [5.0, 10.0]

    static let logButtonCheckmarkDuration = 0.2
    static let momentumFlowTotalDuration = 0.65
    static let momentumDropDuration = 0.4
    static let momentumRiseDuration = 0.5
    static let momentumRiseDelay = 0.15
    static let skipFadeUpDuration = 0.45
    static let exerciseCompletionBeatDuration = 0.2
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
}
