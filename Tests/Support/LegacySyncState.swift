@testable import WorkoutTracker

/// The flattened sync reading the `workout` CLI printed until #590, and the banner spelled
/// through it, kept only so #587's characterization pin (`Tests/Unit/SyncCoordinatorTests.swift`)
/// stays byte-identical.
///
/// Nothing in the app or the CLI composes these sentences any more. The wire carries
/// `SyncOutcome`'s eight names with its payloads raw, and the athlete's sentence is
/// `SyncStatusBannerPresentation`'s. The pin records what the collapse did, so the collapse has to
/// live somewhere, and the test target is the only place it is still true.
extension SyncCoordinator {
    enum State: Equatable {
        case idle, syncing, offline
        case pendingWrites(Int)
        case conflict([String])

        init(_ outcome: SyncOutcome) {
            self =
                switch outcome {
                case .clear: .idle
                case .sheetUnreachable: .offline
                case .writesQueued(let count): .pendingWrites(count)
                case .localWriteFailed(let message): .conflict(["Local write failed: \(message)"])
                case .writesRefused(let messages): .conflict(messages)
                case .noBlockTab: .conflict(["No block tab found in the spreadsheet"])
                case .parseWarnings(let warnings): .conflict(warnings)
                case .historyFillFailed(let message): .conflict(["Exercise History fill failed: \(message)"])
                }
        }
    }

    /// A running step outranks what the last one concluded, because a verdict the next moment may
    /// overturn is not worth showing.
    var state: State { isSyncing ? .syncing : State(outcome) }
}

extension SyncStatusBannerPresentation {
    /// Five outcomes have already collapsed into `.conflict` by the time this sees one, so it
    /// cannot name which happened. The pin only uses it for the one reading `State` can still make
    /// without guessing, that the athlete is shown nothing at all.
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
