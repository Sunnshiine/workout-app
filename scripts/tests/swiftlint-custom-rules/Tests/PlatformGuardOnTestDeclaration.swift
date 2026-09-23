import Testing

@testable import WorkoutTracker

@Test func everyAssertionGuardedAfterACommentIsFlagged() throws {
    // The day fill is the only value this palette pins.
    #if canImport(AppKit)
        expectRGB(try #require(Theme.palette(for: .day).pressedFill), red: 10 / 255, green: 89 / 255, blue: 54 / 255)
    #endif
}

@Test func letBindingAboveTheGuardIsFlagged() {
    let palette = Theme.palette(for: .night)
    #if canImport(AppKit)
        expectRGB(palette.railSelectedFill, red: 242 / 255, green: 247 / 255, blue: 232 / 255, alpha: 0.14)
    #endif
}

@Test func varBindingAboveTheGuardIsFlagged() {
    var palette = Theme.palette(for: .day)
    #if canImport(AppKit)
        expectRGB(palette.accent, red: 0, green: 1, blue: 0)
    #endif
}

@Test func guardOnTheFirstLineIsFlagged() {
    #if canImport(AppKit)
        expectRGB(Theme.palette(for: .day).ink, red: 0, green: 0, blue: 0)
    #endif
}

@Test func ifElsePairInTheBodyIsFlagged() {
    #if canImport(AppKit)
        expectRGB(Theme.palette(for: .day).ink, red: 0, green: 0, blue: 0)
    #else
        #expect(Theme.palette(for: .day).ink != nil)
    #endif
}

struct PlatformGuardSuite {
    @Test func guardInsideASuiteIsFlagged() {
        #if canImport(AppKit)
            expectRGB(Theme.palette(for: .day).ink, red: 0, green: 0, blue: 0)
        #endif
    }
}

@Test(arguments: [1, 2])
func argumentsOnTheirOwnLineIsFlagged(value: Int) {
    #if canImport(AppKit)
        #expect(value > 0)
    #endif
}

@Test func commentBetweenTheEndifAndTheBraceIsFlagged() {
    #if canImport(AppKit)
        expectRGB(Theme.palette(for: .day).ink, red: 0, green: 0, blue: 0)
    #endif
    // Night has no pinned ink yet.
}

@Test func blankLineAboveTheGuardIsFlagged() {

    #if canImport(AppKit)
        expectRGB(Theme.palette(for: .day).ink, red: 0, green: 0, blue: 0)
    #endif
}

@Test func assertionOutsideTheGuardPasses() throws {
    // The pressed fill is a day value; night stays deferred.
    #if canImport(AppKit)
        expectRGB(try #require(Theme.palette(for: .day).pressedFill), red: 10 / 255, green: 89 / 255, blue: 54 / 255)
    #endif
    #expect(Theme.palette(for: .night).pressedFill == nil)
}

#if canImport(AppKit)
    @Test func guardAroundTheDeclarationPasses() {
        expectRGB(Theme.palette(for: .day).ink, red: 0, green: 0, blue: 0)
    }
#endif

@Test func closureBindingAboveTheGuardIsMissed() {
    let fills = Theme.Appearance.allCases.map { Theme.palette(for: $0).cardFill }
    #if canImport(AppKit)
        expectRGB(fills[0], red: 1, green: 1, blue: 1)
    #endif
}

@Test func statementAboveTheGuardIsMissed() {
    var palette = Theme.palette(for: .day)
    palette.accent = .green
    #if canImport(AppKit)
        expectRGB(palette.accent, red: 0, green: 1, blue: 0)
    #endif
}

@Test func multilineBindingAboveTheGuardIsMissed() {
    let palette = Theme.palette(
        for: .day
    )
    #if canImport(AppKit)
        expectRGB(palette.ink, red: 0, green: 0, blue: 0)
    #endif
}
