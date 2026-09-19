import Foundation
import Testing

enum RepositoryFiles {
    static func existingURL(of relativePath: String) throws -> URL {
        let url = try root().appending(path: relativePath)
        try #require(
            FileManager.default.fileExists(atPath: url.path),
            "\(relativePath) does not exist at \(url.path)"
        )
        return url
    }

    static func text(of relativePath: String) throws -> String {
        try String(contentsOf: existingURL(of: relativePath), encoding: .utf8)
    }

    static func nonEmptySwiftSources(
        under relativeDirectory: String,
        where include: (URL) -> Bool = { _ in true }
    ) throws -> [(name: String, source: String)] {
        let directory = try existingURL(of: relativeDirectory)
        let files = (FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.allObjects ?? [])
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && include($0) }
        try #require(!files.isEmpty, "No Swift files to check under \(relativeDirectory) at \(directory.path)")
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    private static func root() throws -> URL {
        let ancestors = sequence(first: URL(fileURLWithPath: #filePath).deletingLastPathComponent()) {
            $0.path == "/" ? nil : $0.deletingLastPathComponent()
        }
        return try #require(
            ancestors.first { FileManager.default.fileExists(atPath: $0.appending(path: "Package.swift").path) },
            "No Package.swift in any directory above \(#filePath)"
        )
    }
}
