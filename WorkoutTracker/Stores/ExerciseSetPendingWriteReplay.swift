import Foundation

extension ExerciseSet {
    /// Replays a still-queued Notes write onto this Set so a log the coach has not flushed yet does
    /// not vanish when a freshly parsed Block replaces the persisted one.
    ///
    /// Only two tokens move the Set: the skip sentinel and a value that parses as a Set Log. Free
    /// text the parser reads as logged-but-unstructured leaves the Set where it is, as does an
    /// empty value.
    @MainActor
    func apply(_ write: PendingWrite) {
        if write.operation == .delete {
            return clearLog(leaving: .pending)
        }
        guard let value = write.valueToWrite else { return }
        let classification = SetLogToken.classify(value)
        switch (classification.state, classification.setLog) {
        case (.skipped, _):
            clearLog(leaving: .skipped)
        case (.logged, let log?):
            state = .logged
            setLog = log
            unstructuredSetLog = nil
        case (.logged, nil), (.pending, _):
            break
        }
    }

    @MainActor
    private func clearLog(leaving state: SetState) {
        self.state = state
        setLog = nil
        unstructuredSetLog = nil
        loggedAt = nil
    }
}
