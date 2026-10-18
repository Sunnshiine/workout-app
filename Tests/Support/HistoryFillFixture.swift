import Foundation
import SwiftData

@testable import WorkoutTracker

/// An Exercise History fill whose tab scans run at `.userInitiated`, above the default-priority
/// busy loops of `scripts/flake-hunt.sh` and parallel lanes. At the app's `.background`, a host at
/// load ~970 left every fill test in `SyncCoordinatorTests` unfinished after 8 minutes while each
/// other test in the file ran 1000 times (#899).
@MainActor
func makeHistoryFill(
    client: any SheetsClient,
    context: ModelContext,
    index: any LastPerformedIndexing,
    backoff: SheetsBackoff = SheetsBackoff()
) -> ExerciseHistoryFill {
    ExerciseHistoryFill(client: client, context: context, index: index, backoff: backoff, scanPriority: .userInitiated)
}

/// Serves one grid per tab, and can fail or throttle a named tab so a test can drive every
/// arm of the Exercise History fill's halt rule. Records the tabs it was asked for, in order.
final class HistoryFillStubClient: SheetsClient, @unchecked Sendable {
    let titles: [String]
    let grids: [String: SheetGrid]
    let unreadableTabs: Set<String>
    let transientFailureTabs: Set<String>
    let recorder: TabFetchRecorder

    init(
        titles: [String],
        grids: [String: SheetGrid],
        unreadableTabs: Set<String> = [],
        transientFailureTabs: Set<String> = [],
        recorder: TabFetchRecorder = TabFetchRecorder()
    ) {
        self.titles = titles
        self.grids = grids
        self.unreadableTabs = unreadableTabs
        self.transientFailureTabs = transientFailureTabs
        self.recorder = recorder
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { titles }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        await recorder.record(tabName)
        if unreadableTabs.contains(tabName) { throw URLError(.userAuthenticationRequired) }
        if transientFailureTabs.contains(tabName) { throw SheetsError.http(429) }
        return SheetSnapshot(values: grids[tabName] ?? [])
    }

    func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {}
}

actor TabFetchRecorder {
    private var fetchedTabs: [String] = []

    func record(_ tab: String) {
        fetchedTabs.append(tab)
    }

    func tabs() -> [String] {
        fetchedTabs
    }
}

private struct HistoryFillIngestFailure: Error, LocalizedError {
    var errorDescription: String? { "the index is full" }
}

/// An index that refuses every new entry, so a test can drive the halt the athlete hears about.
/// Its retract accepts the call and does nothing, so the retractions a sync makes for a current
/// tab with no Set Logs (#812) do not halt it first.
@MainActor
final class RefusingIndex: LastPerformedIndexing {
    func ingest(_ entries: [LastPerformedEntry]) throws { throw HistoryFillIngestFailure() }
    func entryCount(baseName: String) -> Int { 0 }
    func retract(fullName: String, source: String) throws {}
}

/// A current Block tab whose single Squat Set carries no log yet.
func currentGridWithPendingSquat() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "C13": "5/1/2026",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8"
        ],
        rows: 20,
        cols: 60
    )
}

/// A historical Block tab holding one logged Set of `exerciseName`.
func historicalGrid(exerciseName: String, log: String, date: String) -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "C13": date,
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": exerciseName, "D15": "1", "F15": "5", "H15": "RPE8",
            "K15": log
        ],
        rows: 20,
        cols: 60
    )
}
