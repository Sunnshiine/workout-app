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

private let installedProductTypes: Set<String> = [
    "com.apple.product-type.application",
    "com.apple.product-type.app-extension"
]

/// Product types that ship no code into the installed app, so their folders are doctor's business
/// only when a build is running. Every target has to land in this set or `installedProductTypes`,
/// because an inclusion list on its own is one more list that goes stale in silence, which is the
/// defect this whole file exists to pin.
private let uninstalledProductTypes: Set<String> = [
    "com.apple.product-type.bundle.unit-test",
    "com.apple.product-type.bundle.ui-testing"
]

/// Every folder Xcode compiles or copies into the installed app or its extension (ADR-0017). The
/// predicate is `productType` rather than a list of target names, because a name list would be one
/// more hand-maintained copy of exactly the kind this test exists to pin.
private func buildableFoldersDeclaredByTheProject() throws -> Set<String> {
    let objects = try projectObjects()
    let targets = objects.values.filter { $0["isa"] as? String == "PBXNativeTarget" }
    let unclassified = Set(targets.compactMap { $0["productType"] as? String })
        .subtracting(installedProductTypes)
        .subtracting(uninstalledProductTypes)
    try #require(
        unclassified.isEmpty,
        """
        \(projectFile) holds a target of unclassified productType \(unclassified.sorted()).
        Decide whether it ships code into the installed app, then add it to installedProductTypes
        or uninstalledProductTypes in this file.
        """
    )

    let installed = targets.filter { installedProductTypes.contains($0["productType"] as? String ?? "") }
    let groups = installed.flatMap { $0["fileSystemSynchronizedGroups"] as? [String] ?? [] }
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
/// walking up through the `PBXGroup` that holds it. This assumes every group on the way up is
/// `sourceTree = "<group>"`, which is the only kind Xcode writes here. A group anchored to
/// `SOURCE_ROOT` instead would resolve to a folder that does not exist, and the caller fails on
/// that rather than quietly comparing a wrong path.
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

/// Matches the shell assignment rather than the text `sources=(` anywhere, so prose that mentions
/// the array does not count as a second one, and reads on to the closing paren, so the folders may
/// wrap across lines. Three other branches in this stack edit `verify.sh`, and both are edits
/// someone could reasonably make there.
private func buildableFoldersDoctorWatches() throws -> (folders: Set<String>, line: Int) {
    let lines = try RepositoryFiles.text(of: verifyScript)
        .split(separator: "\n", omittingEmptySubsequences: false)
    let assignments = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("sources=(") }
    try #require(
        assignments.count == 1,
        "\(verifyScript) holds \(assignments.count) `sources=(` assignments, expected exactly one"
    )

    let start = assignments[0]
    let closing = try #require(
        lines[start...].firstIndex { $0.contains(")") },
        "the sources=( assignment at \(verifyScript):\(start + 1) never closes"
    )
    let array = lines[start...closing].joined(separator: " ")
    let folders = Set(
        array.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
            .split(whereSeparator: \.isWhitespace).map(String.init)
    )
    try #require(!folders.isEmpty, "sources=() at \(verifyScript):\(start + 1) is empty")
    return (folders, start + 1)
}
