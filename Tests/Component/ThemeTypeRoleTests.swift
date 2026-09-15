import SwiftUI
import Testing

@testable import WorkoutTracker

/// The type role table transcribed back from DESIGN.md, so a typography regression fails in the
/// macOS `swift test` pass. `FontPlumbingTests` stays the UIKit-only proof that a row reaches a
/// real `UIFont`.

@Test func everyTypeRoleHasAStyle() {
    let styles = Dictionary(uniqueKeysWithValues: Theme.TypeRole.allCases.map { ($0, $0.style) })
    #expect(styles.count == 22)
}

@Test(arguments: [
    (Theme.TypeRole.exerciseName, Theme.TypeStyle(face: .fraunces, size: 33, weight: 490, lineHeight: 1.10)),
    (.ceremonyTitle, Theme.TypeStyle(face: .fraunces, size: 38, weight: 490, lineHeight: 1.10)),
    (.connectTitle, Theme.TypeStyle(face: .fraunces, size: 36, weight: 490)),
    (.sheetTitle, Theme.TypeStyle(face: .fraunces, size: 24, weight: 490, lineHeight: 1.1, opticalSize: 22)),
    (.supersetPartner, Theme.TypeStyle(face: .fraunces, size: 20, weight: 490, lineHeight: 1.10, opticalSize: 20)),
    (.weightEntry, Theme.TypeStyle(face: .sourceSans3, size: 46, weight: 700, tabular: true, tracking: -0.69)),
    (.logCapsule, Theme.TypeStyle(face: .sourceSans3, size: 18, weight: 650, tabular: true, tracking: 0.18)),
    (.setNumber, Theme.TypeStyle(face: .sourceSans3, size: 16, weight: 700, tabular: true)),
    (.setOf, Theme.TypeStyle(face: .sourceSans3, size: 14, weight: 500, tabular: true)),
    (.railChipValue, Theme.TypeStyle(face: .sourceSans3, size: 17, weight: 700, tabular: true)),
    (.railChipGlyph, Theme.TypeStyle(face: .sourceSans3, size: 13, weight: 500)),
    (.fieldLabel, Theme.TypeStyle(face: .sourceSans3, size: 12, weight: 600)),
    (.coachNote, Theme.TypeStyle(face: .sourceSans3, size: 15, weight: 400, lineHeight: 1.45)),
    (.runline, Theme.TypeStyle(face: .sourceSans3, size: 13.5, weight: 600, tabular: true)),
    (.runlineSecondary, Theme.TypeStyle(face: .sourceSans3, size: 13.5, weight: 500, tabular: true)),
    (.lastPerformed, Theme.TypeStyle(face: .sourceSans3, size: 12.5, weight: 400, tabular: true, lineHeight: 1.5)),
    (.queuePill, Theme.TypeStyle(face: .sourceSans3, size: 13, weight: 600, tabular: true)),
    (.historyChip, Theme.TypeStyle(face: .sourceSans3, size: 12, weight: 600, tabular: true)),
    (.blockTitle, Theme.TypeStyle(face: .sourceSans3, size: 28, weight: 700, tracking: -0.28)),
    (.cadence, Theme.TypeStyle(face: .sourceSans3, size: 11, weight: 600)),
    (.statsValue, Theme.TypeStyle(face: .sourceSans3, size: 26, weight: 700, tabular: true)),
    (.statsKey, Theme.TypeStyle(face: .sourceSans3, size: 12.5, weight: 600))
])
func typeRoleCarriesItsDesignTokens(role: Theme.TypeRole, expected: Theme.TypeStyle) {
    #expect(role.style == expected)
}

#if !canImport(UIKit)
    @Test func frauncesAndSourceSansRolesResolveToTheirBundledFamilies() {
        #expect(Theme.font(.exerciseName) == Font.custom("Fraunces", fixedSize: 33).weight(.medium))
        #expect(Theme.font(.weightEntry) == Font.custom("Source Sans 3", fixedSize: 46).weight(.bold))
    }

    @Test func everyTypeRoleResolvesToItsFaceSizeAndWeight() {
        for role in Theme.TypeRole.allCases {
            let style = role.style
            let expected = Font.custom(style.face.familyName, fixedSize: style.size)
                .weight(Theme.swiftUIWeight(style.weight))
            #expect(Theme.font(role) == expected, "\(role) did not resolve to its row in the table")
        }
    }
#endif

@Test(arguments: [
    (249.0, Font.Weight.light),
    (250.0, .regular),
    (349.0, .regular),
    (350.0, .regular),
    (449.0, .regular),
    (450.0, .medium),
    (549.0, .medium),
    (550.0, .semibold),
    (649.0, .semibold),
    (650.0, .bold),
    (749.0, .bold),
    (750.0, .heavy)
])
func weightAxisMapsToTheSwiftUIWeightBucket(axis: Double, expected: Font.Weight) {
    #expect(Theme.swiftUIWeight(axis) == expected)
}
