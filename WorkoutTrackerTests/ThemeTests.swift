import SwiftUI
import Testing

@testable import WorkoutTracker

@Test func themeGradientHasTwoStops() {
    let stops = Theme.gradientStops
    #expect(stops.count == 2)
}

@Test func themeGradientStartsWithCharcoal() {
    let stop = Theme.gradientStops[0]
    #expect(stop.location == 0)
}

@Test func themeGradientEndsWithWarmAmber() {
    let stop = Theme.gradientStops[1]
    #expect(stop.location == 1)
}

@Test func themeCardCornerRadiusIs16() {
    #expect(Theme.cardCornerRadius == 16)
}

@Test func themeCardSpacingExists() {
    #expect(Theme.cardSpacing > 0)
}
