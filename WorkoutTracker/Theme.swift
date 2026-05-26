import SwiftUI

enum Theme {
    static let gradientStops: [Gradient.Stop] = [
        .init(color: Color(red: 0.04, green: 0.04, blue: 0.04), location: 0),
        .init(color: Color(red: 0.07, green: 0.07, blue: 0.075), location: 1)
    ]

    static let gradient = LinearGradient(
        stops: gradientStops,
        startPoint: .top,
        endPoint: .bottom
    )

    static let accent = Color(red: 0.831, green: 0.686, blue: 0.216)

    static let cardCornerRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 16
}
