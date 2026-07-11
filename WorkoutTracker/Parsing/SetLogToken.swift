import Foundation

/// The Set Log wire format: a single Notes-cell token is the app's serialized form for one Set's
/// state. It is either empty (Pending), the `skip` sentinel (Skipped), a structured Set Log
/// `{weight}x{reps}@{RPE}` (Logged), or free text (Unstructured Set Log). This module owns that
/// correspondence between a raw token and a Set State — the single place parsing, writing, sync,
/// and diagnostics read the format's definition, so they cannot drift (ADR-0010 applied at the
/// token level; ADR-0005 for the `skip` sentinel).
///
/// The list layer — how a compact aggregate Notes cell is split into and joined from per-Set
/// tokens — stays in the shared `splitSheetNotesList` / `joinedSheetNotesList` codec, which this
/// module reuses rather than re-implementing.
enum SetLogToken {
    /// The Set-level sentinel a coach sees in the Set Log list when a Set is Skipped (ADR-0005:
    /// `skip` is Set-level state written into the Set Log list). Every write/parse/audit path
    /// references this constant instead of a bare `"skip"` literal.
    static let skipSentinel = "skip"

    /// One raw Notes token classified into its Set State plus any parsed logs.
    struct Classification: Equatable {
        let state: SetState
        let setLog: SetLog?
        let unstructuredSetLog: String?
    }

    /// Maps a raw Notes token to its Set State and any structured / unstructured Set Log:
    /// empty → Pending, case-insensitive `skip` → Skipped, a parseable `{weight}x{reps}@{RPE}` →
    /// Logged with a structured Set Log, anything else → Logged with an Unstructured Set Log.
    static func classify(_ raw: String) -> Classification {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return Classification(state: .pending, setLog: nil, unstructuredSetLog: nil)
        }
        if value.caseInsensitiveCompare(skipSentinel) == .orderedSame {
            return Classification(state: .skipped, setLog: nil, unstructuredSetLog: nil)
        }
        if let log = SetLog(formatted: value) {
            return Classification(state: .logged, setLog: log, unstructuredSetLog: nil)
        }
        return Classification(state: .logged, setLog: nil, unstructuredSetLog: value)
    }

    /// Whether a token is a Set-Log-list value: empty (Pending), the `skip` sentinel (Skipped), or
    /// a parseable structured Set Log (Logged). Free text is not — it is a Coach Note / Legacy Log.
    static func isSetLogListValue(_ value: String) -> Bool {
        value.isEmpty
            || value.caseInsensitiveCompare(skipSentinel) == .orderedSame
            || SetLog(formatted: value) != nil
    }

    /// Whether a Notes value is a compact aggregate header: splitting it via `splitSheetNotesList`
    /// yields more than one entry, no more than `setCount` entries, and every entry is a
    /// Set-Log-list value. This gates whether the anchor Notes cell is read as Set Logs vs treated
    /// as a Coach Note / Legacy Log.
    static func isCompactAggregateHeader(_ value: String, setCount: Int) -> Bool {
        let values = splitSheetNotesList(value)
        guard values.count > 1, values.count <= setCount else { return false }
        return values.allSatisfy(isSetLogListValue)
    }
}
