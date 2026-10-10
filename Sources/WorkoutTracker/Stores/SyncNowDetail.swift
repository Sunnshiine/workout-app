enum SyncNowDetail {
    static func text(outcome: SyncOutcome, isSyncing: Bool, hasSheet: Bool) -> String {
        if isSyncing {
            return "Syncing..."
        }

        switch outcome {
        case .clear:
            return hasSheet ? "Refresh workout state" : "Connect a sheet first"
        case .sheetUnreachable:
            return "Offline"
        case .writesQueued(let count):
            return count == 1 ? "1 unsynced log" : "\(count) unsynced logs"
        case .localWriteFailed:
            return "Log not saved"
        case .writesRefused:
            return "Log not written"
        case .noBlockTab:
            return "No block tab"
        case .parseWarnings:
            return "Synced with a note"
        case .historyFillFailed:
            return "History incomplete"
        }
    }
}
