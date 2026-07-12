import Foundation
import Testing

@testable import WorkoutTracker

@Test func fillProgressSurfacesTabAndCounts() {
    let presentation = HistoryFillProgressPresentation(
        LastPerformedBackfillProgress(tab: "Block 25", tabsCompleted: 2, tabsToScan: 3)
    )

    // Per-tab progress in the warm voice: an honest, moving detail line, never a dead spinner.
    #expect(presentation.detail == "Block 25 · 2 of 3")
    #expect(presentation.message.isEmpty == false)
    #expect(presentation.fraction == 2.0 / 3.0)
}

@Test func fillProgressFractionGuardsAgainstZeroUpperBound() {
    // The queued count is an upper bound; a degenerate zero total never divides by zero and clamps.
    let presentation = HistoryFillProgressPresentation(
        LastPerformedBackfillProgress(tab: "Block 27", tabsCompleted: 1, tabsToScan: 0)
    )

    #expect(presentation.fraction == 1)
}
