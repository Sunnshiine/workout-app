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

@Test func coverageOfOneFileUnderTwoPathSpellingsScoresAsOneFile() throws {
    let root = try makeTree(["Sources/A.swift": "func a() {\n    one()\n    two()\n    three()\n}\n"])
    let physical = "/private" + root
    try #require(FileManager.default.fileExists(atPath: physical + "/Sources/A.swift"))
    let lcov = """
        SF:\(physical)/Sources/A.swift
        DA:2,3
        DA:3,0
        DA:4,0
        end_of_record
        SF:\(root)/Sources/A.swift
        DA:2,0
        DA:3,1
        DA:4,0
        end_of_record
        """

    let report = Scorer.score(
        scanned: [
            ScannedFunction(
                file: "Sources/A.swift",
                name: "a()",
                kind: .function,
                startLine: 1,
                endLine: 5,
                cc: 1,
                nestedSpans: []
            )
        ],
        coverage: SourceScan.relativizeCoverage(LCOV.parse(text: lcov), root: root),
        threshold: 6
    )

    let row = try #require(report.functions.first)
    #expect(row.linesInstrumented == 3)
    #expect(row.linesCovered == 2)
}
