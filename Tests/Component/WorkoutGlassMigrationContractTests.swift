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

@Test func moveOnCelebrationUsesSharedLensCornerRadius() throws {
    let source = try String(
        contentsOf: workoutGlassMigrationSourceRoot.appending(path: "WorkoutTracker/Views/MoveOnCelebrationView.swift"),
        encoding: .utf8
    )

    #expect(!source.contains("private static let lensCornerRadius"))
    #expect(source.contains("Theme.lensCornerRadius"))
}
