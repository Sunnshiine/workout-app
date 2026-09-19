import Foundation

/// Decides the Last Set RPE mirror write implied by one Set State transition, so that
/// `log`, `skip` and `deleteLog` stop each deciding it. CONTEXT.md defines the mirror.
struct LastSetRPEMirror {
    static let column = PendingWriteColumn.lastSetRPE

    let operation: PendingWriteOperation
    let valueToWrite: String?
    let expectedCurrentValue: String

    /// An upsert is unconditional but a clear is guarded. Re-writing an unchanged RPE still
    /// reconciles the cell against the coach's copy, while a delete locked to `""` would
    /// conflict against whatever the coach had typed there.
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
