import Foundation

/// The Last Set RPE mirror: column I's copy of the RPE the athlete reported on the final
/// Set of an Exercise. It is derived from that one Set Log and holds no state of its own,
/// so every Set State transition the write path applies to that Set implies exactly one
/// answer here. `WorkoutStore` asks this type for the answer rather than deciding it once
/// per transition. Where the write lands is `SheetWriter`'s business (ADR-0003, ADR-0010).
struct LastSetRPEMirror {
    static let column = PendingWriteColumn.lastSetRPE

    let operation: PendingWriteOperation
    let valueToWrite: String?
    let expectedCurrentValue: String

    /// The write column I needs now that `set` has taken a new Set State, given the RPE
    /// its Set Log carried before. `nil` when the transition leaves column I alone.
    ///
    /// Writing is unconditional and clearing is not. An upsert of an unchanged RPE still
    /// reconciles the cell against the coach's copy, while a delete locked to an empty
    /// cell would ask the Sheet to confirm nothing.
    init?(after set: ExerciseSet, replacing previous: RPE?) {
        guard set.isFinalSetOfExercise else { return nil }

        if let rpe = set.setLog?.rpe {
            operation = .upsert
            valueToWrite = rpe.label
            expectedCurrentValue = previous?.label ?? ""
        } else {
            guard let previous else { return nil }
            operation = .delete
            valueToWrite = nil
            expectedCurrentValue = previous.label
        }
    }
}
