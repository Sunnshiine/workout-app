import Foundation
import Testing

/// The repo root, reached from this file at Tests/Component/<file>.swift.
private var wireTokenSourceRoot: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// The one file allowed to spell the bare `skip` wire token: the module that owns the sentinel
/// (`SetLogToken.skipSentinel`). Every other non-view site must reference the constant.
private let skipSentinelOwner = "SetLogToken.swift"

/// Grep gate for PRD #328: after consolidating the Set Log wire format, no non-view Swift source
/// may hand-copy the bare `"skip"` sentinel literal — a straggler would silently keep the format
/// definition in two places. View code is out of scope (ADR-0010 concerns the wire format, not
/// presentation), and the token module is the canonical owner of the literal.
@Test func noBareSkipWireTokenLiteralOutsideTheTokenModule() throws {
    let root = wireTokenSourceRoot.appending(path: "WorkoutTracker")
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    var offenders: [String] = []

    while let url = enumerator?.nextObject() as? URL {
        guard url.pathExtension == "swift" else { continue }
        if url.path.contains("/Views/") { continue }
        if url.lastPathComponent == skipSentinelOwner { continue }

        let source = try String(contentsOf: url, encoding: .utf8)
        if source.contains("\"skip\"") {
            offenders.append(url.lastPathComponent)
        }
    }

    #expect(
        offenders.isEmpty,
        "Bare \"skip\" wire-token literal found in non-view Swift: \(offenders). Use SetLogToken.skipSentinel."
    )
}
