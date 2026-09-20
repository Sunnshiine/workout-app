import Foundation
import SwiftData

/// The deepest historical Block tab the Exercise History fill has successfully ingested for one
/// spreadsheet — the resume point after a failed-tab halt (ADR-0012).
///
/// The fill scans Block tabs newest-first. When a tab fails — a transient 429/5xx that outlasts
/// the Sheets client's backoff budget, or any non-transient error — the fill **halts** rather than
/// skipping, because a hole in the middle corrupts the coverage count and triggers pointless deeper
/// scanning. This cursor records the last tab read before the halt so the next sync resumes from the
/// tab just deeper than it instead of re-reading everything already on device. Re-ingesting a tab is
/// idempotent via `source` dedup, so the cursor is advisory — it only spares redundant reads. It is
/// cleared when a fill finishes cleanly (coverage reached, or tabs exhausted without a failure).
@Model
final class HistoryFillCursor {
    @Attribute(.unique) var spreadsheetId: String
    var deepestIngestedTab: String
    var updatedAt: Date

    init(spreadsheetId: String, deepestIngestedTab: String, updatedAt: Date = .now) {
        self.spreadsheetId = spreadsheetId
        self.deepestIngestedTab = deepestIngestedTab
        self.updatedAt = updatedAt
    }
}
