import Foundation

/// The canonical form and similarity that `ExerciseName.isSameMovement(as:)` compares Base Names
/// with (ADR-0013).
///
/// Two Exercises are the same **Movement** when their canonicalized Base Names fuzzy-match.
/// Everything here runs at query time, anchor-relative to a viewed Exercise — nothing is
/// persisted and no clustering is computed. Rule changes (a new abbreviation, a threshold
/// tweak) therefore apply instantly to every existing row with no migration.
enum MovementMatching {
    /// Normalized-Levenshtein similarity threshold. At 0.8 typos (0.86) and plurals (0.93)
    /// merge while genuine modifiers — "Paused Bench Press" vs "Bench Press" (0.61) — split.
    static let threshold = 0.8

    /// Abbreviations the coach uses interchangeably with their spelled-out forms. This table
    /// is also the never-merge escape hatch: it grows explicit expansions as a data fix, no
    /// algorithm change. `rdl` is deliberately absent — it is never spelled out.
    private static let abbreviations: [String: String] = [
        "bp": "bench press",
        "comp": "competition",
        "db": "dumbbell",
        "bb": "barbell",
        "bw": "bodyweight"
    ]

    /// Deterministic canonical form of a Base Name: lowercase, map punctuation to spaces, collapse
    /// whitespace, then expand each token through the abbreviation table. The Cadence is already off,
    /// because only `ExerciseName.base` reaches here.
    static func canonicalize(_ base: String) -> String {
        let spaced = base.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        let tokens = String(spaced).split(separator: " ").map(String.init)
        return tokens.map { abbreviations[$0] ?? $0 }.joined(separator: " ")
    }

    /// Normalized Levenshtein similarity: `1 − distance / max(length)`, hand-rolled.
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        let longest = max(left.count, right.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(levenshtein(left, right)) / Double(longest)
    }

    private static func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for (i, leftChar) in lhs.enumerated() {
            current[0] = i + 1
            for (j, rightChar) in rhs.enumerated() {
                let substitution = previous[j] + (leftChar == rightChar ? 0 : 1)
                current[j + 1] = min(substitution, previous[j + 1] + 1, current[j] + 1)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
