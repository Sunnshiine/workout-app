import Foundation

/// What a finished sync step left the athlete to deal with.
///
/// One case per result, because each one asks something different of them. A local write that
/// failed lost a Set Log outright. A refused write is still in the store but will never be
/// retried (ADR-0003), so the app saying so is the only copy of that news. A spreadsheet with no
/// Block tab is a setup problem nobody caused and puts no Set Log at risk. A parse warning or a
/// stalled Exercise History fill is a successful sync with a footnote.
///
/// Being in flight is not an outcome. `SyncCoordinator.isSyncing` answers that.
///
/// Each message is carried as the step produced it. The sentence the athlete reads is
/// `SyncStatusBannerPresentation`'s, and the flattened wording the CLI prints is
/// `SyncCoordinator.State`'s.
enum SyncOutcome: Equatable, Sendable {
    /// Nothing to report.
    case clear
    /// The app could not record a Set Log in the local store. That log is gone.
    case localWriteFailed(String)
    /// The Sheet could not be reached.
    case sheetUnreachable
    /// The upload failed and this many Set Logs are still queued. The next flush attempts them
    /// again.
    case writesQueued(Int)
    /// The Sheet cell no longer held what the app expected, so the write was refused rather than
    /// overwrite the coach (ADR-0003). The Set Logs stay in the store and are never retried.
    case writesRefused([String])
    /// The spreadsheet holds no Block tab, so there is nothing to sync.
    case noBlockTab
    /// The sync succeeded and the Block is cached. The layout interpreter flagged something.
    case parseWarnings([String])
    /// The sync succeeded and the Session is usable. A background Exercise History fill stopped.
    case historyFillFailed(String)
}

extension SyncOutcome {
    /// What a Sheet read reports once the Block is cached: no warnings means the interpreter had
    /// nothing to flag.
    init(parseWarnings: [String]) {
        self = parseWarnings.isEmpty ? .clear : .parseWarnings(parseWarnings)
    }

    /// What a pending-write flush reports: no refusals means every queued write landed, or there
    /// was nothing queued.
    init(refusedWrites: [String]) {
        self = refusedWrites.isEmpty ? .clear : .writesRefused(refusedWrites)
    }

    /// The verdict one sync reports, from what its Sheet read concluded and what the pending-write
    /// flush it ran first concluded.
    ///
    /// The read speaks last and speaks for everything it just measured, so by default its verdict
    /// is the sync's. Two rules cut across that.
    ///
    /// A refused write survives a read that went well, because it is the one verdict no later step
    /// can make stale: the Sheet will never be asked to take that write again (ADR-0003), so
    /// dropping it leaves the athlete with no copy of the message. A queued write is the opposite.
    /// The next flush measures the queue again and reports it again, so a clean read clears it.
    ///
    /// An unreachable Sheet and a missing Block tab replace even a refused write, because both end
    /// the sync with no Block to show and that is the larger thing to say.
    static func sync(sheetRead: SyncOutcome, flush: SyncOutcome) -> SyncOutcome {
        switch (sheetRead, flush) {
        case (.sheetUnreachable, _), (.noBlockTab, _): sheetRead
        case (_, .writesRefused): flush
        default: sheetRead
        }
    }
}
