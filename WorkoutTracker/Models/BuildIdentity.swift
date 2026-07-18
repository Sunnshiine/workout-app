import Foundation

/// The app's own build identity, read from the `Info.plist` keys the TestFlight
/// workflows stamp (`GitCommit`, `PRNumber`, `Branch`, `RunNumber`) plus the
/// version pair. Falls back gracefully in unstamped local builds.
struct BuildIdentity {
    let version: String
    let build: String
    let commit: String?
    let prNumber: String?
    let branch: String?
    let runNumber: String?

    /// The running app's identity.
    static var current: BuildIdentity { BuildIdentity(info: Bundle.main.infoDictionary ?? [:]) }

    init(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let string = info[key] as? String, !string.isEmpty else { return nil }
            return string
        }
        version = value("CFBundleShortVersionString") ?? "0.0"
        build = value("CFBundleVersion") ?? "0"
        commit = value("GitCommit")
        prNumber = value("PRNumber")
        branch = value("Branch")
        runNumber = value("RunNumber")
    }

    /// A CI-stamped build carries a commit; a local build does not.
    var isStamped: Bool { commit != nil }

    /// A single caption line, e.g. `0.372 (7) · 6aba617 · PR #372`. The commit
    /// and `PR #N` segments appear only when stamped; local builds append
    /// `local build`.
    var compactLine: String {
        var segments = ["\(version) (\(build))"]
        if let commit { segments.append(commit) }
        if let prNumber { segments.append("PR #\(prNumber)") }
        if !isStamped { segments.append("local build") }
        return segments.joined(separator: " · ")
    }

    /// The full, multi-line identity for the clipboard.
    var copyText: String {
        var lines = ["Version: \(version) (\(build))"]
        if let commit { lines.append("Commit: \(commit)") }
        if let branch { lines.append("Branch: \(branch)") }
        if let prNumber { lines.append("PR: #\(prNumber)") }
        if let runNumber { lines.append("Run: \(runNumber)") }
        if !isStamped { lines.append("Local build (no CI stamp)") }
        return lines.joined(separator: "\n")
    }
}
