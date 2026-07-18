import Foundation
import Testing

/// Guards the hand-authored Icon Composer bundles (`*.icon/icon.json`).
///
/// Regression for the archive-build failure where `actool` crashed with
/// `Cannot Open "AppIcon.icon"` / `attempt to insert nil object from objects[0]`.
/// Root cause: an explicit JSON `null` (`"blur-material": null`) in a group.
/// `actool` reads the value, gets a Cocoa `nil`, and inserts it into an
/// `NSArray` while selecting Icon Composer items — throwing
/// `NSInvalidArgumentException` and failing the asset-catalog compile.
///
/// Icon Composer omits keys it has no value for rather than writing `null`,
/// so any explicit `null` anywhere in an `icon.json` is the smell we reject.
/// The real seam is `actool`, which does not run under `swift test`; this
/// static scan locks down the exact pattern that broke the build.
@Suite struct AppIconAssetTests {
    /// Repo root, derived from this source file's location (`Tests/Unit/…`).
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Unit
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    private static func iconManifests() throws -> [URL] {
        let appDir = repoRoot.appendingPathComponent("WorkoutTracker")
        let entries = try FileManager.default.contentsOfDirectory(
            at: appDir, includingPropertiesForKeys: nil
        )
        return entries
            .filter { $0.pathExtension == "icon" }
            .map { $0.appendingPathComponent("icon.json") }
            .sorted { $0.path < $1.path }
    }

    /// Depth-first walk collecting JSON paths whose value is an explicit `null`.
    private func explicitNullPaths(in value: Any, path: String) -> [String] {
        if value is NSNull { return [path] }
        if let dict = value as? [String: Any] {
            return dict.sorted { $0.key < $1.key }.flatMap {
                explicitNullPaths(in: $0.value, path: "\(path)/\($0.key)")
            }
        }
        if let array = value as? [Any] {
            return array.enumerated().flatMap {
                explicitNullPaths(in: $0.element, path: "\(path)[\($0.offset)]")
            }
        }
        return []
    }

    @Test func iconManifestsContainNoExplicitNulls() throws {
        let manifests = try Self.iconManifests()
        #expect(!manifests.isEmpty, "Expected at least one *.icon/icon.json to guard")

        for manifest in manifests {
            let data = try Data(contentsOf: manifest)
            let json = try JSONSerialization.jsonObject(with: data)
            let nulls = explicitNullPaths(in: json, path: "")
            #expect(
                nulls.isEmpty,
                """
                \(manifest.lastPathComponent) in \(manifest.deletingLastPathComponent().lastPathComponent) \
                contains explicit null value(s) at \(nulls) — actool rejects these \
                and the archive build fails. Omit the key instead of writing null.
                """
            )
        }
    }
}
