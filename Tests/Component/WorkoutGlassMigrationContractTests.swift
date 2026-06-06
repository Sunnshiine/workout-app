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
