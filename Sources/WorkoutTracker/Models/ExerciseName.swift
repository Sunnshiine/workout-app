import Foundation

/// An Exercise's name: its **Entered Name**, the coach's name cell as written, and the **Base Name**
/// and **Cadence** that split out of it (CONTEXT.md). The split happens here and nowhere else, so a
/// `base` never carries a Cadence and a `cadence` always agrees with the prefix on `entered`.
///
/// `entered` is the identity: the Sheet write's anchor match, a queued write's Exercise, and the
/// `exercise_history` dedup key (ADR-0012) all compare it byte for byte. `base` is what the athlete
/// reads (PRODUCT.md, *Hide the spreadsheet*). `base` and `cadence` derive from `entered`, so two names
/// are equal exactly when their entered text is, and two Exercises that share a base name under
/// different Cadences stay two Exercises.
struct ExerciseName: Hashable, Sendable, ExpressibleByStringLiteral {
    let entered: String
    let base: String
    let cadence: String?

    init(entered: String) {
        self.entered = entered
        if let match = entered.wholeMatch(of: /^(\d+(?:-\d+)?:\d+(?:-\d+)?:\d+(?:-\d+)?)\s+(.+)$/) {
            cadence = String(match.1)
            base = String(match.2)
        } else {
            cadence = nil
            base = entered
        }
    }

    init(stringLiteral entered: String) {
        self.init(entered: entered)
    }
}
