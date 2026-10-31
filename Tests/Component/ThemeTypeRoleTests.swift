import SwiftUI
import Testing

@testable import WorkoutTracker

@Test func everyTypeRoleHasAStyle() {
    let styles = Dictionary(uniqueKeysWithValues: Theme.TypeRole.allCases.map { ($0, $0.style) })
    #expect(styles.count == 25)
}

@Test func everyTypeRoleHasACurve() {
    let curves = Dictionary(uniqueKeysWithValues: Theme.TypeRole.allCases.map { ($0, Theme.TypeScale.curve($0)) })
    #expect(curves.count == 25)
}

@Test(arguments: [
    (Theme.TypeRole.exerciseName, Theme.TypeStyle(face: .fraunces, size: 33, weight: 490, lineHeight: 1.1)),
    (.ceremonyTitle, Theme.TypeStyle(face: .fraunces, size: 36, weight: 490, lineHeight: 1.1)),
    (.connectTitle, Theme.TypeStyle(face: .fraunces, size: 36, weight: 490, lineHeight: 1.1)),
    (.sheetTitle, Theme.TypeStyle(face: .fraunces, size: 24, weight: 490, lineHeight: 1.1, opticalSize: 22)),
    (.heading, Theme.TypeStyle(face: .sourceSans3, size: 17, weight: 600)),
    (.supersetPartner, Theme.TypeStyle(face: .fraunces, size: 20, weight: 490)),
    (.weightEntry, Theme.TypeStyle(face: .sourceSans3, size: 46, weight: 700)),
    (.countdownNumeral, Theme.TypeStyle(face: .sourceSans3, size: 96, weight: 700)),
    (.logCapsule, Theme.TypeStyle(face: .sourceSans3, size: 17, weight: 600)),
    (.setNumber, Theme.TypeStyle(face: .sourceSans3, size: 17, weight: 700)),
    (.setOf, Theme.TypeStyle(face: .sourceSans3, size: 15, weight: 400)),
    (.railChipValue, Theme.TypeStyle(face: .sourceSans3, size: 17, weight: 700)),
    (.railChipGlyph, Theme.TypeStyle(face: .sourceSans3, size: 13, weight: 400)),
    (.fieldLabel, Theme.TypeStyle(face: .sourceSans3, size: 12, weight: 600)),
    (.coachNote, Theme.TypeStyle(face: .sourceSans3, size: 15, weight: 400, lineHeight: 1.5)),
    (.runline, Theme.TypeStyle(face: .sourceSans3, size: 13, weight: 600)),
    (.runlineSecondary, Theme.TypeStyle(face: .sourceSans3, size: 13, weight: 400)),
    (.lastPerformed, Theme.TypeStyle(face: .sourceSans3, size: 13, weight: 400)),
    (.queuePill, Theme.TypeStyle(face: .sourceSans3, size: 13, weight: 600)),
    (.historyChip, Theme.TypeStyle(face: .sourceSans3, size: 12, weight: 600)),
    (.blockTitle, Theme.TypeStyle(face: .sourceSans3, size: 28, weight: 700)),
    (.cadence, Theme.TypeStyle(face: .sourceSans3, size: 12, weight: 600)),
    (.statsValue, Theme.TypeStyle(face: .sourceSans3, size: 28, weight: 700)),
    (.statsKey, Theme.TypeStyle(face: .sourceSans3, size: 12, weight: 600)),
    (.sheetCell, Theme.TypeStyle(face: .sourceSans3, size: 12, weight: 400))
])
func typeRoleCarriesItsDesignTokens(role: Theme.TypeRole, expected: Theme.TypeStyle) {
    #expect(role.style == expected)
}

@Test func sourceSansSizesComeFromTheScale() {
    let scale: Set<CGFloat> = [12, 13, 15, 17, 28, 46, 96]
    let weights: Set<Double> = [400, 600, 700]
    for role in Theme.TypeRole.allCases where role.style.face == .sourceSans3 {
        #expect(scale.contains(role.style.size), "\(role) is off the scale at \(role.style.size)pt")
        #expect(weights.contains(role.style.weight), "\(role) is off the weights at \(role.style.weight)")
    }
}

@Test(arguments: [
    (Theme.TypeRole.fieldLabel, 0.01),
    (.runline, 0),
    (.heading, 0),
    (.blockTitle, -0.01),
    (.weightEntry, -0.015),
    (.countdownNumeral, -0.015),
    (.exerciseName, 0),
    (.ceremonyTitle, 0)
])
func trackingOpensCaptionsAndTightensDisplaySansOnly(role: Theme.TypeRole, em: Double) {
    let size = role.style.size
    #expect(role.style.tracking(at: size) == CGFloat(em) * size)
}

@Test func aCaptionScaledToReadingSizeStopsOpening() {
    let caption = Theme.TypeRole.fieldLabel.style
    #expect(caption.tracking(at: 12) > 0)
    #expect(caption.tracking(at: 18) == 0)
}

@Test func denseFloorStopsReferenceLinesAtTwelvePoints() {
    #expect(Theme.TypeRole.lastPerformed.denseFloorScale * Theme.TypeRole.lastPerformed.style.size == 12)
    #expect(Theme.TypeRole.historyChip.denseFloorScale == 1)
}

#if !canImport(UIKit)
    @Test func frauncesAndSourceSansRolesResolveToTheirBundledFamilies() {
        #expect(Theme.font(.exerciseName, at: .large) == Font.custom("Fraunces", fixedSize: 33).weight(.medium))
        #expect(Theme.font(.weightEntry, at: .accessibility5) == Font.custom("Source Sans 3", fixedSize: 46).weight(.bold))
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
