import Foundation
import Testing

private let projectFile = "WorkoutTracker.xcodeproj/project.pbxproj"
private let verifyScript = ".agents/skills/verify/verify.sh"

/// `verify.sh doctor` compares every folder in its `sources=(...)` array against the built app's
/// mtime. A buildable folder missing from that array is one whose edits a stale build hides, which
/// is the failure doctor exists to catch. That array is a hand-copy of the project's own list, and
/// nothing linked the copy back to the original (issue #656).
@Test func doctorWatchesEveryBuildableFolderTheInstalledAppBuilds() throws {
    let declared = try buildableFoldersDeclaredByTheProject()
    let watched = try buildableFoldersDoctorWatches()

    #expect(
        declared == watched.folders,
        """
        \(verifyScript):\(watched.line) has drifted from \(projectFile).
        Built into the app or its extension, unwatched by doctor: \(declared.subtracting(watched.folders).sorted())
        Watched by doctor, built into neither: \(watched.folders.subtracting(declared).sorted())
        The project decides which folders ship, so make that line read:
        sources=(\(declared.sorted().joined(separator: " ")))
        """
    )
}

/// Every folder Xcode compiles or copies into the installed app or its extension (ADR-0017). The
/// predicate is `productType` rather than a list of target names, because a name list would be one
/// more hand-maintained copy of exactly the kind this test exists to pin.
private func buildableFoldersDeclaredByTheProject() throws -> Set<String> {
    let objects = try projectObjects()
    let installedProductTypes: Set<String> = [
        "com.apple.product-type.application",
        "com.apple.product-type.app-extension"
    ]
    let groups = objects.values
        .filter {
            $0["isa"] as? String == "PBXNativeTarget"
                && installedProductTypes.contains($0["productType"] as? String ?? "")
        }
        .flatMap { $0["fileSystemSynchronizedGroups"] as? [String] ?? [] }
    try #require(!groups.isEmpty, "\(projectFile) declares no buildable folder for any installed target")

    var parentOf: [String: String] = [:]
    for (id, object) in objects {
        for child in object["children"] as? [String] ?? [] { parentOf[child] = id }
    }

    let repository = try RepositoryFiles.existingURL(of: "Package.swift").deletingLastPathComponent()
    return try Set(
        groups.map { group in
            let folder = repositoryPath(ofGroup: group, in: objects, parentOf: parentOf)
            try #require(
                FileManager.default.fileExists(atPath: repository.appending(path: folder).path),
                "\(projectFile) builds \(folder), which does not exist in the repository"
            )
            return folder
        }
    )
}

/// A group's `path` is relative to its parent, so `Sources/WorkoutTracker` only reads whole after
/// walking up through the `PBXGroup` that holds it.
private func repositoryPath(ofGroup group: String, in objects: [String: [String: Any]], parentOf: [String: String]) -> String {
    var components: [String] = []
    var id: String? = group
    while let current = id, let object = objects[current] {
        if let path = object["path"] as? String { components.insert(path, at: 0) }
        id = parentOf[current]
    }
    return components.joined(separator: "/")
}

/// A pbxproj is an OpenStep property list, so Foundation parses it whole. Scraping the text instead
/// would tie this test to Xcode's indentation.
private func projectObjects() throws -> [String: [String: Any]] {
    let data = try Data(contentsOf: RepositoryFiles.existingURL(of: projectFile))
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    return try #require((plist as? [String: Any])?["objects"] as? [String: [String: Any]], "\(projectFile) has no objects map")
}

private func buildableFoldersDoctorWatches() throws -> (folders: Set<String>, line: Int) {
    let declarations = try RepositoryFiles.text(of: verifyScript)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
        .compactMap { index, line -> (folders: Set<String>, line: Int)? in
            guard let open = line.range(of: "sources=("),
                let close = line[open.upperBound...].firstIndex(of: ")")
            else { return nil }
            return (Set(line[open.upperBound..<close].split(whereSeparator: \.isWhitespace).map(String.init)), index + 1)
        }
    try #require(declarations.count == 1, "\(verifyScript) holds \(declarations.count) sources=(...) arrays, expected one")

    let watched = declarations[0]
    try #require(!watched.folders.isEmpty, "sources=() at \(verifyScript):\(watched.line) is empty")
    return watched
}
