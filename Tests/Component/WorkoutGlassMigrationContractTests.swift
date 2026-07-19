import Foundation
import Testing

private let workoutGlassMigrationFiles = [
    "WorkoutTracker/Views/OnboardingView.swift",
    "WorkoutTracker/Views/MoveOnCelebrationView.swift",
    "WorkoutTracker/Views/SessionView.swift"
]

private var workoutGlassMigrationSourceRoot: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@Test func structuralGlassViewsUseWorkoutGlassHelper() throws {
    let forbiddenPatterns = [
        "GlassEffectContainer",
        ".glassEffect(",
        ".buttonStyle(.glass)",
        ".glassEffectID("
    ]

    for file in workoutGlassMigrationFiles {
        let source = try String(contentsOf: workoutGlassMigrationSourceRoot.appending(path: file), encoding: .utf8)

        for pattern in forbiddenPatterns {
            #expect(!source.contains(pattern), "\(file) still contains \(pattern)")
        }
    }
}

@Test func moveOnCelebrationDoesNotDefineLocalLensCornerRadius() throws {
    let source = try String(
        contentsOf: workoutGlassMigrationSourceRoot.appending(path: "WorkoutTracker/Views/MoveOnCelebrationView.swift"),
        encoding: .utf8
    )

    #expect(!source.contains("private static let lensCornerRadius"))
}

@Test func moveOnCelebrationDoesNotExposeBloomTestHook() throws {
    let source = try String(
        contentsOf: workoutGlassMigrationSourceRoot.appending(path: "WorkoutTracker/Views/MoveOnCelebrationView.swift"),
        encoding: .utf8
    )

    #expect(!source.contains("disablesBloom"))
    #expect(!source.contains("UITEST_DISABLE_CELEBRATION_BLOOM"))
}

@Test func moveOnCelebrationUsesEnvironmentThemePalette() throws {
    let source = try String(
        contentsOf: workoutGlassMigrationSourceRoot.appending(path: "WorkoutTracker/Views/MoveOnCelebrationView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("@Environment(\\.themePalette) private var palette"))
    #expect(!source.contains("Theme.palette(for: .sageLight)"))
}

@Test func moveOnCelebrationOwnsReduceMotionSafeCeremony() throws {
    let source = try String(
        contentsOf: workoutGlassMigrationSourceRoot.appending(path: "WorkoutTracker/Views/MoveOnCelebrationView.swift"),
        encoding: .utf8
    )

    // The ceremony grows the stem and lands the bird on the wing ease; Reduced
    // Motion crossfades to the fully-grown end state (no orbit, no elapsed nucleus).
    #expect(source.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
    #expect(source.contains("if reduceMotion"))
    #expect(source.contains("Theme.wingAnimation"))
    #expect(source.contains("CeremonyBranch"))
    #expect(source.contains("PerchedSongbird"))
    #expect(!source.contains("TimelineView(.animation"))
    #expect(!source.contains("move-on-celebration-orbit"))
}

@Test func moveOnCelebrationHasNoGlassAndNoElapsedNucleus() throws {
    let source = try String(
        contentsOf: workoutGlassMigrationSourceRoot.appending(path: "WorkoutTracker/Views/MoveOnCelebrationView.swift"),
        encoding: .utf8
    )

    // The colophon is absent while the bird is present; the ceremony wears no glass.
    #expect(!source.contains("workoutGlass"))
    #expect(!source.contains("WorkoutGlassContainer"))
    #expect(!source.contains("elapsed"))
    #expect(!source.contains("orbit"))
}

// The Sunbird colophon is the one surviving glass element (DESIGN.md §6): retired
// Liquid Glass surfaces cannot leak back, so the raw glass primitive lives only in
// the colophon's file.
@Test func sunbirdColophonIsTheOneSurvivingGlassElement() throws {
    let source = try String(
        contentsOf: workoutGlassMigrationSourceRoot.appending(path: "WorkoutTracker/Views/Sunbird.swift"),
        encoding: .utf8
    )

    #expect(source.contains("struct SunbirdColophon"))
    #expect(source.contains("struct PerchedSongbird"))
    #expect(source.contains(".glassEffect(.regular, in: .circle)"))
    // The 28pt honesty floor is enforced, not assumed.
    #expect(source.contains("max(28, diameter)"))
}

// The connect screen is the second bird perch: the perched songbird centered with
// the glass colophon, flat calm (no glass card of its own).
@Test func connectScreenPerchesTheSongbirdAndColophon() throws {
    let source = try String(
        contentsOf: workoutGlassMigrationSourceRoot.appending(path: "WorkoutTracker/Views/OnboardingView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("SunbirdColophon(diameter: 40)"))
    #expect(source.contains("PerchedSongbird("))
    #expect(source.contains("Theme.font(.connectTitle)"))
}
