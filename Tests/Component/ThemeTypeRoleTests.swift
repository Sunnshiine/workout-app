import SwiftUI
import Testing

@testable import WorkoutTracker

@Test func everyTypeRoleHasAStyle() {
    let styles = Dictionary(uniqueKeysWithValues: Theme.TypeRole.allCases.map { ($0, $0.style) })
    #expect(styles.count == 22)
}

#if !canImport(UIKit)
    @Test func frauncesAndSourceSansRolesResolveToTheirBundledFamilies() {
        #expect(Theme.font(.exerciseName) == Font.custom("Fraunces", fixedSize: 33).weight(.medium))
        #expect(Theme.font(.weightEntry) == Font.custom("Source Sans 3", fixedSize: 46).weight(.bold))
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
