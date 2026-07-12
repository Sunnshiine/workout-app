import Foundation

/// The fill-in-progress affordance's presentation model (revised `DESIGN.md` §Exercise History
/// Sheet — "While the history index is still filling…", PRD #357 §4, sub-issue #366).
///
/// Projects one `LastPerformedBackfillProgress` tick from the observer seam into muted, warm-voice
/// copy plus a determinate fraction, so the Exercise History sheet shows honest, moving progress
/// rather than a dead spinner. It lives in the quiet Last Performed reference vocabulary — no mint —
/// and the view stays a dumb renderer.
struct HistoryFillProgressPresentation: Equatable, Sendable {
    /// The warm-voice headline — playful but quiet.
    let message: String
    /// The per-tab detail: which Block tab just landed and how far this run has reached. Surfacing
    /// the tab keeps the affordance honestly moving instead of an indeterminate spinner.
    let detail: String
    /// A determinate fraction in `0...1` for a muted progress bar — ingested tabs over the queued
    /// upper bound. Never mint.
    let fraction: Double

    init(_ progress: LastPerformedBackfillProgress) {
        message = "Digging up more of your history…"
        detail = "\(progress.tab) · \(progress.tabsCompleted) of \(progress.tabsToScan)"
        // `tabsToScan` is an upper bound and the coverage rule may finish early; guard the divide
        // and clamp so a degenerate count can never overflow the bar or divide by zero.
        let total = max(progress.tabsToScan, progress.tabsCompleted, 1)
        fraction = min(1, Double(progress.tabsCompleted) / Double(total))
    }
}
