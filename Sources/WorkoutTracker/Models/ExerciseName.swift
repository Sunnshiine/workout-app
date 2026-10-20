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

    /// The Movement-level question (ADR-0013, Last Performed's third tier and Exercise History):
    /// whether any of the two Base Names' options (`MovementMatching.options(of:)`) canonicalize to
    /// the same text or fuzzy-match at `MovementMatching.threshold`. Coarser than equality, so
    /// "Standing Calve Raises" and "Standing Calf Raise" are one Movement while "Paused Bench Press"
    /// and "Bench Press" are two, and the choice "Leg Press or Hack Squat" is one Movement with each
    /// of its options.
    func isSameMovement(as other: ExerciseName) -> Bool {
        let theirs = MovementMatching.options(of: other.base)
        return MovementMatching.options(of: base).contains { left in
            theirs.contains { right in
                left == right || MovementMatching.similarity(left, right) >= MovementMatching.threshold
            }
        }
    }

    /// Whether an Exercise History entry spells its Base Name differently from the viewed
    /// Exercise's beyond letter case, which is when the entry shows its own name *as "…"*
    /// (ADR-0013). A Cadence difference alone never annotates.
    func differsBeyondCase(from other: ExerciseName) -> Bool {
        base.lowercased() != other.base.lowercased()
    }
}
