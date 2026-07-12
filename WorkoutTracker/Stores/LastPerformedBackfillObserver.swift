/// Per-tab progress published by the Exercise History fill as it advances (ADR-0012).
///
/// The fill scans historical Block tabs newest-first; each successfully ingested tab emits one of
/// these so the UI can show honest, moving progress rather than a dead spinner. The affordance that
/// renders it is a separate ticket (#366); this is only the seam it reads.
struct LastPerformedBackfillProgress: Equatable, Sendable {
    /// The historical tab just ingested.
    let tab: String
    /// How many historical tabs this fill run has ingested so far, including this one.
    let tabsCompleted: Int
    /// The number of historical tabs queued for this run — an upper bound, since the coverage
    /// stopping rule may finish before reaching them all.
    let tabsToScan: Int
}

@MainActor
protocol LastPerformedBackfillObserving {
    /// Published once per historical tab as the fill ingests it.
    func lastPerformedBackfillDidProgress(_ progress: LastPerformedBackfillProgress)
    func lastPerformedBackfillDidFinish()
}

extension LastPerformedBackfillObserving {
    /// The fill halts or completes without any conformer having to observe intermediate progress.
    func lastPerformedBackfillDidProgress(_ progress: LastPerformedBackfillProgress) {}
}

@MainActor
struct NoopLastPerformedBackfillObserver: LastPerformedBackfillObserving {
    func lastPerformedBackfillDidFinish() {}
}
