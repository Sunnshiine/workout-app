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

    static let cardCornerRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 16
    static let pillCornerRadius: CGFloat = 8
    static let pillMinHeight: CGFloat = 86
    static let pillSpacing: CGFloat = 10
    static let rpeGridSpacing: CGFloat = 8
    static let rpeGridCellHeight: CGFloat = 48
    static let weightIncrementThreshold = 100.0
    static let lightWeightIncrementOptions = [2.5, 5.0]
    static let heavyWeightIncrementOptions = [5.0, 10.0]
}
