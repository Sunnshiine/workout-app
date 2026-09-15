import Foundation

extension ExerciseSet {
    /// Replays a still-queued Notes write onto this Set so a log the coach has not flushed yet does
    /// not vanish when a freshly parsed Block replaces the persisted one.
    ///
    /// A `.delete` deliberately leaves `unstructuredSetLog` alone; only `setLog` and `loggedAt` clear.
    @MainActor
    func apply(_ write: PendingWrite) {
        if write.operation == .delete {
            state = .pending
            setLog = nil
            loggedAt = nil
            return
        }
        guard let value = write.valueToWrite else { return }
        let classification = SetLogToken.classify(value)
        switch classification.state {
        case .skipped:
            state = .skipped
            setLog = nil
            loggedAt = nil
        case .logged:
            if let log = classification.setLog {
                state = .logged
                setLog = log
            }
        case .pending:
            break
        }
    }
}
