import Foundation

/// The Set-Log list layer: a compact aggregate / per-Prescription-Line Notes cell holds a
/// comma-separated list of per-Set tokens. This codec owns the read-modify-write idiom the write
/// planner, the diagnostics audit, and the multi-line reader each used to spell inline — split the
/// cell into tokens, collapse a lone-empty split result to an empty list, pad up to a Set's list
/// position, read or overwrite the token at that position, then rejoin trimming trailing empties.
///
/// It builds on the shared `splitSheetNotesList` / `joinedSheetNotesList` free functions (which
/// stay) and sits alongside `SetLogToken`, the per-token wire format: `SetLogToken` classifies one
/// token into a Set State; `SetLogList` addresses tokens by Set position within the list.
struct SetLogList: Equatable {
    /// The per-Set tokens, with a lone-empty split result already collapsed to an empty list so
    /// padding and positional writes start from zero.
    private(set) var tokens: [String]

    /// Splits a raw Notes-cell value into its per-Set tokens, collapsing a single empty entry (an
    /// empty or whitespace-only cell) to an empty list.
    init(cell: String) {
        var values = splitSheetNotesList(cell)
        if values.count == 1, values[0].isEmpty {
            values = []
        }
        tokens = values
    }

    /// The token at `position`, or empty when the list is shorter than `position` — a Set whose log
    /// has not been written yet.
    func token(at position: Int) -> String {
        position < tokens.count ? tokens[position] : ""
    }

    /// Overwrites the token at `position`, padding the list with empty entries up to that position
    /// first so the write lands at the Set's own slot.
    mutating func setToken(_ token: String, at position: Int) {
        while tokens.count <= position {
            tokens.append("")
        }
        tokens[position] = token
    }

    /// Rejoins the tokens into a Notes-cell value, trimming trailing empties (delete-to-empty and
    /// trailing-empty trimming) via `joinedSheetNotesList`.
    var cellValue: String {
        joinedSheetNotesList(tokens)
    }
}
