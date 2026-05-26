import SwiftUI

enum Theme {
    static let gradientStops: [Gradient.Stop] = [
        .init(color: Color(red: 0.15, green: 0.15, blue: 0.16), location: 0),
        .init(color: Color(red: 0.6, green: 0.35, blue: 0.1), location: 1)
    ]

    static let gradient = LinearGradient(
        stops: gradientStops,
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardCornerRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 16
}
