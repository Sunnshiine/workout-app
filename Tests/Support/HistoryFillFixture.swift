import Foundation

@testable import WorkoutTracker

/// Serves one grid per tab, and can fail, stall, or throttle a named tab so a test can drive every
/// arm of the Exercise History fill's halt rule. Records the tabs it was asked for, in order.
final class HistoryFillStubClient: SheetsClient, @unchecked Sendable {
    let titles: [String]
    let grids: [String: SheetGrid]
    let unreadableTabs: Set<String>
    let transientFailureTabs: Set<String>
    let suspendedTabs: Set<String>
    let recorder: TabFetchRecorder

    init(
        titles: [String],
        grids: [String: SheetGrid],
        unreadableTabs: Set<String> = [],
        transientFailureTabs: Set<String> = [],
        suspendedTabs: Set<String> = [],
        recorder: TabFetchRecorder = TabFetchRecorder()
    ) {
        self.titles = titles
        self.grids = grids
        self.unreadableTabs = unreadableTabs
        self.transientFailureTabs = transientFailureTabs
        self.suspendedTabs = suspendedTabs
        self.recorder = recorder
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { titles }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        await recorder.record(tabName)
        if unreadableTabs.contains(tabName) { throw URLError(.userAuthenticationRequired) }
        if transientFailureTabs.contains(tabName) { throw SheetsError.http(429) }
        if suspendedTabs.contains(tabName) {
            await recorder.waitForRelease()
        }
        return SheetSnapshot(values: grids[tabName] ?? [])
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}

actor TabFetchRecorder {
    private var fetchedTabs: [String] = []
    private var released = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func record(_ tab: String) {
        fetchedTabs.append(tab)
    }

    func tabs() -> [String] {
        fetchedTabs
    }

    func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private struct HistoryFillIngestFailure: Error, LocalizedError {
    var errorDescription: String? { "the index is full" }
}

/// An index that refuses everything, so a test can drive the halt the athlete hears about.
@MainActor
final class RefusingIndex: LastPerformedIndexing {
    func ingest(_ entries: [LastPerformedEntry]) throws { throw HistoryFillIngestFailure() }
    func entryCount(baseName: String) -> Int { 0 }
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
