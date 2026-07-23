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

@Test func moveOnCelebrationRetiresTheAnimatedOrbitForAByteStableCeremony() throws {
    let source = try String(
        contentsOf: workoutGlassMigrationSourceRoot.appending(path: "WorkoutTracker/Views/MoveOnCelebrationView.swift"),
        encoding: .utf8
    )

    // The ceremony still observes reduced motion (it gates the Crisp haptic), but the
    // per-frame timing nucleus is gone — the source of the #482 baseline flake (PRD #497
    // slice 7). No live TimelineView, no orbit, so the render is byte-stable.
    #expect(source.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
    #expect(source.contains("guard !reduceMotion else { return }"))
    #expect(!source.contains("TimelineView(.animation"))
    #expect(!source.contains("move-on-celebration-orbit"))
}
