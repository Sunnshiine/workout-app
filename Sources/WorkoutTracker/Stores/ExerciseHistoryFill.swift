import Foundation
import Observation
import SwiftData

/// The Exercise History fill (**Exercise History fill** in `CONTEXT.md`, ADR-0012).
///
/// A failed tab — a transient 429/5xx that outlasts the backoff budget, or any non-transient error —
/// **halts** the run instead of skipping the tab, because a silent hole in the middle corrupts the
/// coverage count. The deepest tab read before the halt is persisted as a cursor so the next run
/// resumes from the tab just deeper than it; re-ingest is idempotent via `source` dedup, so the
/// cursor only spares redundant reads. The cursor is cleared on a clean finish.
@MainActor
@Observable
final class ExerciseHistoryFill {
    /// What a sync already knows once the current Block has landed.
    struct Request: Equatable, Sendable {
        let spreadsheetId: String
        let tabTitles: [String]
        let currentTab: String
        /// Cadence-stripped base names of every Exercise in the current Block: the unit coverage
        /// counts in (ADR-0012), so full names never enter the fill.
        let baseNames: Set<String>
    }

    /// One per-tab tick, published after each ingested tab.
    struct Progress: Equatable, Sendable {
        /// The historical tab just ingested.
        let tab: String
        /// How many historical tabs this run has ingested so far, including this one.
        let tabsCompleted: Int
        /// The tabs queued for this run — an upper bound, since the coverage rule may stop before
        /// reaching them all.
        let tabsToScan: Int
    }

    /// How one run ended.
    enum Outcome: Equatable, Sendable {
        /// No historical Block tabs, or a current Block with no Exercises. The cursor is untouched.
        case nothingToScan
        /// Every base name holds `ExerciseHistorySheetPresentation.entryLimit` entries. Zero tabs
        /// means coverage already held before any read.
        case coverageReached(tabsIngested: Int)
        /// Every historical tab below the cursor was read without reaching coverage.
        case tabsExhausted(tabsIngested: Int)
        /// A tab stopped the run. The cursor still names the deepest tab this run ingested, and
        /// stays absent when the halt came before any tab landed.
        case halted(tab: String, reason: HaltReason, tabsIngested: Int)
    }

    /// Why a tab stopped the run.
    enum HaltReason: Equatable, Sendable {
        /// A non-transient error (auth, malformed response) propagated from the fetch.
        case unreadable
        /// Transient 429/5xx failures outlasted the backoff schedule.
        case retriesExhausted
        /// The tab was read but the index refused it. The only halt the athlete hears about today.
        case indexRejected(String)
    }

    /// The latest tick while a run is in flight, `nil` otherwise. The Exercise History sheet renders
    /// its fill affordance from this and drops it the moment the run ends by any path.
    private(set) var progress: Progress?

    private let client: any SheetsClient
    private let context: ModelContext
    private let index: any LastPerformedIndexing
    private let backoff: SheetsBackoff

    init(
        client: any SheetsClient,
        context: ModelContext,
        index: any LastPerformedIndexing,
        backoff: SheetsBackoff = SheetsBackoff()
    ) {
        self.client = client
        self.context = context
        self.index = index
        self.backoff = backoff
    }

    /// One traversal, awaitable. Safe to call again after any outcome: the cursor and `source`
    /// dedup make a repeat converge on the same index.
    func run(_ request: Request) async -> Outcome {
        defer { progress = nil }
        guard !scannableTabs(for: request).isEmpty else { return .nothingToScan }
        guard !hasCoverage(for: request.baseNames) else {
            clearCursor(spreadsheetId: request.spreadsheetId)
            return .coverageReached(tabsIngested: 0)
        }

        let tabsToScan = sortedHistoricalTabs(
            from: request.tabTitles,
            excluding: request.currentTab,
            deeperThan: cursorTab(spreadsheetId: request.spreadsheetId)
        )
        var tabsIngested = 0

        for tab in tabsToScan {
            if case .halted(let reason) = await ingest(tab, spreadsheetId: request.spreadsheetId) {
                return .halted(tab: tab, reason: reason, tabsIngested: tabsIngested)
            }

            advanceCursor(spreadsheetId: request.spreadsheetId, to: tab)
            tabsIngested += 1
            progress = Progress(tab: tab, tabsCompleted: tabsIngested, tabsToScan: tabsToScan.count)

            if hasCoverage(for: request.baseNames) {
                clearCursor(spreadsheetId: request.spreadsheetId)
                return .coverageReached(tabsIngested: tabsIngested)
            }
        }

        // Tabs exhausted without reaching coverage: a clean finish, so start fresh next run.
        clearCursor(spreadsheetId: request.spreadsheetId)
        return .tabsExhausted(tabsIngested: tabsIngested)
    }
}

extension ExerciseHistoryFill {
    /// The historical tabs this request could read at all, before the cursor narrows them. Empty
    /// means there is nothing to scan: no historical Block tabs, or a Block with no Exercises.
    private func scannableTabs(for request: Request) -> [String] {
        guard !request.baseNames.isEmpty else { return [] }
        return sortedHistoricalTabs(from: request.tabTitles, excluding: request.currentTab)
    }

    /// The coverage stopping rule (ADR-0012). Counting by base name (not Movement level) may fetch
    /// a tab Movement matching didn't strictly need; that over-fetch is accepted (#357).
    private func hasCoverage(for baseNames: Set<String>) -> Bool {
        baseNames.allSatisfy { baseName in
            index.entryCount(baseName: baseName) >= ExerciseHistorySheetPresentation.entryLimit
        }
    }

    private enum TabIngestion {
        case ingested
        case halted(HaltReason)
    }

    /// Scan off the main actor, then ingest on it. Anything short of `.ingested` halts the run.
    private func ingest(_ tab: String, spreadsheetId: String) async -> TabIngestion {
        let client = client
        let backoff = backoff
        let scan: TabScan
        do {
            scan = try await Task.detached(priority: .background) {
                try await Self.scan(tab: tab, spreadsheetId: spreadsheetId, client: client, backoff: backoff)
            }.value
        } catch {
            return .halted(.unreadable)
        }

        guard case .fetched(let occurrences) = scan else { return .halted(.retriesExhausted) }

        if !occurrences.isEmpty {
            do {
                try index.ingest(occurrences.map(LastPerformedEntry.init))
            } catch {
                return .halted(.indexRejected(error.localizedDescription))
            }
        }
        return .ingested
    }

    /// One historical tab's outcome, computed off the main actor.
    private enum TabScan: Sendable {
        /// The tab was read (however small) and yielded these Last Performed occurrences.
        case fetched([LastPerformedOccurrence])
        case failed
    }

    nonisolated private static func scan(
        tab: String,
        spreadsheetId: String,
        client: any SheetsClient,
        backoff: SheetsBackoff
    ) async throws -> TabScan {
        switch try await client.fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tab, retrying: backoff) {
        case .failed:
            return .failed
        case .fetched(let snapshot):
            let parsed = SheetParser().parse(snapshot: snapshot, tabName: tab)
            return .fetched(LastPerformedExtractor.occurrences(from: parsed.block))
        }
    }

    private func cursorTab(spreadsheetId: String) -> String? {
        cursor(spreadsheetId: spreadsheetId)?.deepestIngestedTab
    }

    private func cursor(spreadsheetId: String) -> HistoryFillCursor? {
        let descriptor = FetchDescriptor<HistoryFillCursor>(
            predicate: #Predicate { $0.spreadsheetId == spreadsheetId }
        )
        return try? context.fetch(descriptor).first
    }

    private func advanceCursor(spreadsheetId: String, to tab: String) {
        if let existing = cursor(spreadsheetId: spreadsheetId) {
            existing.deepestIngestedTab = tab
            existing.updatedAt = .now
        } else {
            context.insert(HistoryFillCursor(spreadsheetId: spreadsheetId, deepestIngestedTab: tab))
        }
        try? context.save()
    }

    private func clearCursor(spreadsheetId: String) {
        guard let cursor = cursor(spreadsheetId: spreadsheetId) else { return }
        context.delete(cursor)
        try? context.save()
    }
}
