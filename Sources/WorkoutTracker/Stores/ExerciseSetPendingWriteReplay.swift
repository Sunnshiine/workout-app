import Foundation

extension ExerciseSet {
    @MainActor
    func replay(_ write: PendingWrite) {
        switch write.column {
        case .notes: apply(write)
        case .setFlag: applySetFlag(write)
        case .lastSetRPE: break
        }
    }

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

    /// Replays a queued Set Flag over what the Sheet's Cell Note said, so its standing survives a
    /// freshly parsed Block. A flag the Sheet already holds while its write waits to converge stays
    /// Unsynced until the flush confirms it.
    @MainActor
    private func applySetFlag(_ write: PendingWrite) {
        guard let flag = write.setFlag else { return }
        record(flag, standing: write.status == .conflict ? .refused : .unsynced)
    }
}

extension PendingWrite {
    @MainActor
    var setFlag: SetFlag? {
        valueToWrite.flatMap { SetFlagLine(parsing: $0) }?.flag
    }
}
