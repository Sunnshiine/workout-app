import Foundation

public enum SourceScan {
    public static func matches(path: String, glob: String) -> Bool {
        fnmatch(glob, path, 0) == 0
    }

    public static func isExcluded(path: String, excludes: [String]) -> Bool {
        excludes.contains { matches(path: path, glob: $0) }
    }

    /// Absolute paths under `root` become root-relative; anything else is returned unchanged.
    public static func relativize(path: String, root: String) -> String {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
    }

    /// Root-relative `.swift` paths under each source directory, sorted, excludes applied.
    public static func swiftFiles(root: String, sources: [String], excludes: [String]) -> [String] {
        var found: [String] = []
        for source in sources {
            let directory = URL(fileURLWithPath: root).appendingPathComponent(source)
            guard
                let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
            else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let relative = relativize(path: url.standardizedFileURL.path, root: root)
                guard !isExcluded(path: relative, excludes: excludes) else { continue }
                found.append(relative)
            }
        }
        return Array(Set(found)).sorted()
    }

    /// Re-keys parsed lcov data by root-relative path so it joins with scanned rows.
    public static func relativizeCoverage(_ coverage: [String: [Int: Int]], root: String) -> [String: [Int: Int]] {
        var result: [String: [Int: Int]] = [:]
        for (path, lines) in coverage {
            let key = relativize(path: URL(fileURLWithPath: path).standardizedFileURL.path, root: root)
            result[key] =
                result[key].map { existing in
                    existing.merging(lines) { $0 + $1 }
                } ?? lines
        }
        return result
    }
}
