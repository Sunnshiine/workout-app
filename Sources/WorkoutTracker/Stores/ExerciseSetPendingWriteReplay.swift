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
            return markPending()
        }
        guard let value = write.valueToWrite else { return }
        let classification = SetLogToken.classify(value)
        switch (classification.state, classification.setLog) {
        case (.skipped, _):
            markSkipped()
        case (.logged, let log?):
            markLogged(log, at: write.createdAt)
        case (.logged, nil), (.pending, _):
            break
        }
    }
}
