import Foundation
import Testing

@testable import CRAPKit

private func makeTree(_ files: [String: String]) throws -> String {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("crap-sourcescan-\(UUID().uuidString)")
    for (path, contents) in files {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.path
}

@Test func swiftFilesReturnsRootRelativePathsUnderEverySource() throws {
    let root = try makeTree([
        "Sources/WorkoutTracker/Models/Block.swift": "struct Block {}",
        "Sources/WorkoutTracker/Views/Home.swift": "struct Home {}",
        "Sources/WorkoutCLI/Workout.swift": "struct Workout {}",
        "Sources/WorkoutTracker/Models/notes.md": "not Swift"
    ])

    let files = try SourceScan.swiftFiles(
        root: root,
        sources: ["Sources/WorkoutTracker", "Sources/WorkoutCLI"],
        excludes: ["Sources/WorkoutTracker/Views/*"]
    )

    #expect(files == ["Sources/WorkoutCLI/Workout.swift", "Sources/WorkoutTracker/Models/Block.swift"])
}

@Test func swiftFilesRefusesASourceDirectoryThatDoesNotExist() throws {
    let root = try makeTree(["Sources/WorkoutTracker/Models/Block.swift": "struct Block {}"])

    #expect {
        try SourceScan.swiftFiles(root: root, sources: ["WorkoutTracker"], excludes: [])
    } throws: { error in
        error.localizedDescription == "no source directory at WorkoutTracker"
    }
}

@Test func swiftFilesRefusesASourceDirectoryWithNoSwiftFile() throws {
    let root = try makeTree([
        "Sources/WorkoutTracker/Models/Block.swift": "struct Block {}",
        "Sources/WorkoutCLI/README.md": "prose only"
    ])

    #expect {
        try SourceScan.swiftFiles(root: root, sources: ["Sources/WorkoutTracker", "Sources/WorkoutCLI"], excludes: [])
    } throws: { error in
        error.localizedDescription == "source directory Sources/WorkoutCLI holds no .swift file"
    }
}
