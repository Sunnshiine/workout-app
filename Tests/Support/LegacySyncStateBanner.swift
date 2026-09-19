@testable import WorkoutTracker

extension SyncStatusBannerPresentation {
    /// #587's characterization pin spells the banner through `SyncCoordinator.State`, the flat
    /// reading the `workout` CLI still prints (#590 retires it). Five outcomes have already
    /// collapsed into `.conflict` by the time this sees one, so it cannot name which happened and
    /// the app no longer asks it to. It exists so the pin file stays byte-identical, and the pin
    /// only uses it where the athlete is shown nothing at all — the one reading `State` can still
    /// make without guessing.
    init?(state: SyncCoordinator.State) {
        let outcome: SyncOutcome =
            switch state {
            case .idle, .syncing: .clear
            case .offline: .sheetUnreachable
            case .pendingWrites(let count): .writesQueued(count)
            case .conflict(let messages): .writesRefused(messages)
            }
        self.init(outcome: outcome, isSyncing: state == .syncing)
    }
}
