import Foundation
import Testing

/// The one file allowed to spell the bare `skip` wire token: the module that owns the sentinel
/// (`SetLogToken.skipSentinel`). Every other non-view site must reference the constant.
private let skipSentinelOwner = "SetLogToken.swift"

/// The Spoken Set grammar hears the word an athlete says, which happens to spell the wire token,
/// and never writes it. That file may declare the word once; any other bare literal there is a
/// hand-copied wire token like anywhere else.
private let spokenSkipWord = (file: "SpokenWords.swift", declaration: "static let spokenSkipWord = \"skip\"")

/// Grep gate for PRD #328: after consolidating the Set Log wire format, no non-view Swift source
/// may hand-copy the bare `"skip"` sentinel literal — a straggler would silently keep the format
/// definition in two places. View code is out of scope (ADR-0010 concerns the wire format, not
/// presentation), and the token module is the canonical owner of the literal.
@Test func noBareSkipWireTokenLiteralOutsideTheTokenModule() throws {
    let isCandidate = { (url: URL) in
        !url.path.contains("/Views/") && url.lastPathComponent != skipSentinelOwner
    }
    let sources =
        try RepositoryFiles.nonEmptySwiftSources(
            under: "Sources/WorkoutTracker",
            mustContain: "Parsing/\(skipSentinelOwner)",
            where: isCandidate
        )
        + RepositoryFiles.nonEmptySwiftSources(
            under: "App",
            mustContain: "WorkoutTrackerApp.swift",
            where: isCandidate
        )
    let offenders = sources.filter { file in
        let checked =
            file.name == spokenSkipWord.file
            ? file.source.replacing(spokenSkipWord.declaration, with: "", maxReplacements: 1) : file.source
        return checked.contains("\"skip\"")
    }
    .map(\.name)

    #expect(
        offenders.isEmpty,
        "Bare \"skip\" wire-token literal found in non-view Swift: \(offenders). Use SetLogToken.skipSentinel."
    )
}
