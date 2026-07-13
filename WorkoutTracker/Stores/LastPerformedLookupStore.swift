import Foundation
import Observation
import SwiftData

/// Per-tab progress published by the Exercise History fill as it advances (ADR-0012).
///
/// The fill scans historical Block tabs newest-first; each successfully ingested tab emits one of
/// these so the UI can show honest, moving progress rather than a dead spinner. The affordance that
/// renders it is a separate ticket (#366); the owner republishes it to the display as `fillProgress`.
struct LastPerformedBackfillProgress: Equatable, Sendable {
    /// The historical tab just ingested.
    let tab: String
    /// How many historical tabs this fill run has ingested so far, including this one.
    let tabsCompleted: Int
    /// The number of historical tabs queued for this run — an upper bound, since the coverage
    /// stopping rule may finish before reaching them all.
    let tabsToScan: Int
}

/// The single interface onto the Last Performed owner (PRD #330): ingest evidence, count coverage,
/// and receive the backfill's per-tab progress. Callers — the sync coordinator, in particular —
/// hold this one seam rather than a bare `ModelContext` (so ingest can refresh the display snapshot
/// as part of the same operation) or a second observer protocol (so the fill's progress lands on the
/// same owner it already ingests into). The write→refresh pairing and the progress→display republish
/// are no longer caller responsibilities.
@MainActor
protocol LastPerformedIndexing {
    /// Append-only ingest that also refreshes the published display snapshot in the same operation.
    func ingest(_ entries: [LastPerformedEntry]) throws
    /// Number of stored entries whose Cadence-stripped base name matches — the coverage-fill
    /// counting unit (ADR-0012).
    func entryCount(baseName: String) -> Int
    /// Published once per historical tab as the fill ingests it, so the display's fill affordance
    /// tracks honest progress.
    func lastPerformedBackfillDidProgress(_ progress: LastPerformedBackfillProgress)
    /// The fill halted or reached coverage: the owner drops its fill affordance.
    func lastPerformedBackfillDidFinish()
}

extension LastPerformedIndexing {
    /// Ingest-only callers (and the Noop) need not observe intermediate fill progress.
    func lastPerformedBackfillDidProgress(_ progress: LastPerformedBackfillProgress) {}
    func lastPerformedBackfillDidFinish() {}
}

@MainActor
struct NoopLastPerformedIndex: LastPerformedIndexing {
    func ingest(_ entries: [LastPerformedEntry]) throws {}
    func entryCount(baseName: String) -> Int { 0 }
}

/// The single Last Performed owner: it owns the persisted index and the published display snapshot,
/// and it is the one interface for ingest, entry-count coverage, and lookup (PRD #330). Ingesting
/// evidence and refreshing the snapshot the display reads are one operation, so no caller has to
/// remember to pair them.
@MainActor
@Observable
final class LastPerformedLookupStore: LastPerformedIndexing {
    private(set) var snapshot: LastPerformedLookupSnapshot = .empty
    /// The most recent per-tab fill progress while the Exercise History fill is running, or `nil`
    /// once it has reached coverage or exhausted the tabs. The sheet renders its progress affordance
    /// from this (sub-issue #366) and drops it the moment the fill finishes.
    private(set) var fillProgress: LastPerformedBackfillProgress?
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    /// Append-only ingest (ADR-0012), deduped on (`fullName`, `source`), then refresh the snapshot.
    ///
    /// A Session that already has an entry is refreshed in place — this keeps re-ingesting
    /// the same tab idempotent and lets the in-progress current Session's entry track live
    /// logging — while a new Session appends a fresh row. `source` is the dedup key because
    /// unparseable dates degrade to `.distantPast` and cannot distinguish Sessions. Refreshing the
    /// display snapshot is part of the same operation so the write→refresh pairing cannot drift.
    func ingest(_ entries: [LastPerformedEntry]) throws {
        for entry in entries {
            if let existing = existingEntry(fullName: entry.fullName, source: entry.source) {
                existing.baseName = entry.baseName
                existing.resultText = entry.resultText
                existing.performedOn = entry.performedOn
            } else {
                context.insert(entry)
            }
        }
        try context.save()
        refresh()
    }

    /// Number of stored entries whose Cadence-stripped base name matches exactly — the
    /// coverage-fill counting unit (ADR-0012). `baseName` is already Cadence-stripped at
    /// parse time, so this is a plain equality count. Coverage counts by base name (not
    /// Movement level), which may over-fetch a tab Movement matching didn't need — accepted,
    /// erring toward more data on device (#357).
    func entryCount(baseName: String) -> Int {
        let descriptor = FetchDescriptor<LastPerformedEntry>(
            predicate: #Predicate { $0.baseName == baseName }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func lastPerformedBackfillDidProgress(_ progress: LastPerformedBackfillProgress) {
        fillProgress = progress
    }

    func lastPerformedBackfillDidFinish() {
        fillProgress = nil
    }

    private func refresh() {
        let entries = (try? context.fetch(FetchDescriptor<LastPerformedEntry>())) ?? []
        snapshot = LastPerformedLookupSnapshot(entries: entries)
    }

    private func existingEntry(fullName: String, source: String) -> LastPerformedEntry? {
        let descriptor = FetchDescriptor<LastPerformedEntry>(
            predicate: #Predicate { $0.fullName == fullName && $0.source == source }
        )
        return try? context.fetch(descriptor).first
    }
}
