import Foundation

/// The sync banner's words. `text` is the app's own sentence for the outcome; `detail` is the
/// message the step produced, which is the part that names the Exercise or the Block tab.
struct SyncStatusBannerPresentation: Equatable, Sendable {
    let text: String
    let detail: String?
    let accessibilityLabel: String

    init(text: String, detail: String? = nil) {
        self.text = text
        self.detail = detail
        self.accessibilityLabel = detail.map { "Sync status: \(text). \($0)" } ?? "Sync status: \(text)"
    }

    init?(outcome: SyncOutcome, isSyncing: Bool) {
        guard !isSyncing else {
            self.init(text: "Syncing")
            return
        }

        switch outcome {
        case .clear:
            return nil
        case .localWriteFailed(let message):
            self.init(text: "Your log did not save on this phone", detail: message)
        case .sheetUnreachable:
            self.init(text: "Offline")
        case .writesQueued(let count):
            self.init(text: "\(count) unsynced")
        case .writesRefused(let messages):
            self.init(text: "The sheet changed, so your log was not written", detail: messages.first)
        case .noBlockTab:
            self.init(text: "This sheet has no block tab")
        case .parseWarnings(let warnings):
            self.init(text: "Synced, with a note about the sheet", detail: warnings.first)
        case .historyFillFailed(let message):
            self.init(text: "Synced. Exercise History did not finish", detail: message)
        }
    }
}
