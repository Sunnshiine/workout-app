import Foundation

/// What a finished sync step left the athlete to deal with.
///
/// Being in flight is not an outcome. `SyncCoordinator.isSyncing` answers that.
///
/// Messages are carried raw, as the step produced them. The sentence the athlete reads is
/// `SyncStatusBannerPresentation`'s.
enum SyncOutcome: Equatable, Sendable {
    case clear
    /// That Set Log is gone.
    case localWriteFailed(String)
    case sheetUnreachable
    /// The next flush attempts them again.
    case writesQueued(Int)
    /// The Sheet cell no longer held what the app expected, so the write was refused rather than
    /// overwrite the coach (ADR-0003). `markConflict` takes it off the flush queue, which fetches
    /// only `.pending`, so nothing attempts it again.
    case writesRefused([String])
    case noBlockTab
    /// The sync succeeded and the Block is cached.
    case parseWarnings([String])
    /// The sync succeeded and the Session is usable.
    case historyFillFailed(String)
}

extension SyncOutcome {
    init(parseWarnings: [String]) {
        self = parseWarnings.isEmpty ? .clear : .parseWarnings(parseWarnings)
    }

    init(refusedWrites: [String]) {
        self = refusedWrites.isEmpty ? .clear : .writesRefused(refusedWrites)
    }

    /// The verdict one sync reports, from what its Sheet read concluded and what the pending-write
    /// flush it ran first concluded.
    ///
    /// The read speaks last, so its verdict is the sync's, except that a refused write survives a
    /// read that went well. A queued write does not.
    /// #589 reproduced both rather than change behavior while reshaping the type.
    static func sync(sheetRead: SyncOutcome, flush: SyncOutcome) -> SyncOutcome {
        switch (sheetRead, flush) {
        case (.sheetUnreachable, _), (.noBlockTab, _): sheetRead
        case (_, .writesRefused): flush
        default: sheetRead
        }
    }
}
