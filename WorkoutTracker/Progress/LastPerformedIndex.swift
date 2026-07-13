import Foundation
import SwiftData

@MainActor
struct LastPerformedIndex {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
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

    func snapshot() -> LastPerformedLookupSnapshot {
        let entries = (try? context.fetch(FetchDescriptor<LastPerformedEntry>())) ?? []
        return LastPerformedLookupSnapshot(entries: entries)
    }

    /// Append-only ingest (ADR-0012), deduped on (`fullName`, `source`).
    ///
    /// A Session that already has an entry is refreshed in place — this keeps re-ingesting
    /// the same tab idempotent and lets the in-progress current Session's entry track live
    /// logging — while a new Session appends a fresh row. `source` is the dedup key because
    /// unparseable dates degrade to `.distantPast` and cannot distinguish Sessions.
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
    }

    private func existingEntry(fullName: String, source: String) -> LastPerformedEntry? {
        let descriptor = FetchDescriptor<LastPerformedEntry>(
            predicate: #Predicate { $0.fullName == fullName && $0.source == source }
        )
        return try? context.fetch(descriptor).first
    }
}
