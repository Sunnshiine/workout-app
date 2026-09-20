import Foundation
import Testing

// MARK: - Glass is retired to the colophon (ADR-0014 · PRD #497 slice 9)

@Test func workoutGlassHelperFileIsDeleted() throws {
    let views = try RepositoryFiles.existingURL(of: "App/Views")
    #expect(!FileManager.default.fileExists(atPath: views.appending(path: "WorkoutGlass.swift").path))
}

@Test func noViewReferencesTheRetiredGlassSystem() throws {
    // ADR-0014's surviving-glass rule: the only glass element is the Sunbird colophon's disc,
    // which paints raw gradients (SunbirdColophon.swift) and never touched these APIs. After the
    // contract slice no product surface may reference the retired `WorkoutGlass` vocabulary or the
    // system `.glassEffect` / glass button styles it wrapped.
    let forbidden = [
        "workoutGlass(",
        "WorkoutGlassContainer",
        ".workoutGlassID(",
        ".workoutGlassUnion(",
        ".workoutGlassTransition(",
        ".glassEffect(",
        "GlassEffectContainer",
        ".buttonStyle(.glass)",
        ".buttonStyle(.workoutGlass)",
        ".buttonStyle(.workoutGlassProminent)"
    ]

    for (name, source) in try everyAppAndLibrarySource() {
        for token in forbidden {
            #expect(!source.contains(token), "\(name) still references retired glass API \(token)")
        }
    }
}

// MARK: - The retired 8/16/28 radius scale is deleted (token sheet §6)

@Test func retiredRadiusConstantsAreDeletedFromTheme() throws {
    let theme = try RepositoryFiles.text(of: "Sources/WorkoutTracker/Theme.swift")

    for retired in ["cardCornerRadius", "lensCornerRadius", "rowCornerRadius", "sessionTileCornerRadius", "pillCornerRadius"] {
        #expect(!theme.contains(retired), "Theme.swift still defines the retired radius constant \(retired)")
    }
}

@Test func noViewReferencesARetiredRadiusConstant() throws {
    let retired = ["cardCornerRadius", "lensCornerRadius", "rowCornerRadius", "sessionTileCornerRadius", "pillCornerRadius"]
    for (name, source) in try everyAppAndLibrarySource() {
        for constant in retired {
            #expect(!source.contains(constant), "\(name) still references the retired radius constant Theme.\(constant)")
        }
    }
}

// MARK: - Move On ceremony contracts (carried from PRD #497 slice 7)

private func moveOnCelebrationSource() throws -> String {
    try RepositoryFiles.text(of: "App/Views/MoveOnCelebrationView.swift")
}

@Test func moveOnCelebrationDoesNotDefineLocalLensCornerRadius() throws {
    #expect(!(try moveOnCelebrationSource()).contains("private static let lensCornerRadius"))
}

@Test func moveOnCelebrationDoesNotExposeBloomTestHook() throws {
    let source = try moveOnCelebrationSource()
    #expect(!source.contains("disablesBloom"))
    #expect(!source.contains("UITEST_DISABLE_CELEBRATION_BLOOM"))
}

@Test func moveOnCelebrationUsesEnvironmentThemePalette() throws {
    let source = try moveOnCelebrationSource()
    #expect(source.contains("@Environment(\\.themePalette) private var palette"))
    #expect(!source.contains("Theme.palette(for: .sageLight)"))
}

@Test func moveOnCelebrationRetiresTheAnimatedOrbitForAByteStableCeremony() throws {
    let source = try moveOnCelebrationSource()

    // The ceremony still observes reduced motion (it gates the Crisp haptic), but the
    // per-frame timing nucleus is gone — the source of the #482 baseline flake (PRD #497
    // slice 7). No live TimelineView, no orbit, so the render is byte-stable.
    #expect(source.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
    #expect(source.contains("guard !reduceMotion else { return }"))
    #expect(!source.contains("TimelineView(.animation"))
    #expect(!source.contains("move-on-celebration-orbit"))
}

private func everyAppAndLibrarySource() throws -> [(name: String, source: String)] {
    try RepositoryFiles.nonEmptySwiftSources(
        under: "Sources/WorkoutTracker",
        mustContain: "Theme.swift"
    )
        + RepositoryFiles.nonEmptySwiftSources(
            under: "App",
            mustContain: "Views/MoveOnCelebrationView.swift"
        )
}
