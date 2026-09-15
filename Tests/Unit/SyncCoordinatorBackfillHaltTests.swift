import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private struct BackfillIngestFailure: Error, LocalizedError {
    var errorDescription: String? { "the index is full" }
}

private actor BackfillTabLog {
    private var tabs: [String] = []

    func record(_ tab: String) { tabs.append(tab) }
    func recorded() -> [String] { tabs }
}

private final class HaltingBackfillClient: SheetsClient, @unchecked Sendable {
    let titles: [String]
    let grids: [String: SheetGrid]
    let nonTransientFailureTabs: Set<String>
    let log: BackfillTabLog

    init(
        titles: [String],
        grids: [String: SheetGrid],
        nonTransientFailureTabs: Set<String> = [],
        log: BackfillTabLog = BackfillTabLog()
    ) {
        self.titles = titles
        self.grids = grids
        self.nonTransientFailureTabs = nonTransientFailureTabs
        self.log = log
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { titles }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        await log.record(tabName)
        if nonTransientFailureTabs.contains(tabName) { throw URLError(.userAuthenticationRequired) }
        return SheetSnapshot(values: grids[tabName] ?? [])
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}

/// Awaits the detached backfill and optionally refuses to store what it reads.
@MainActor
private final class BackfillIndexProbe: LastPerformedIndexing {
    let failsIngest: Bool
    private(set) var ingestedSources: [String] = []
    private var didFinish = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(failsIngest: Bool = false) {
        self.failsIngest = failsIngest
    }

    func ingest(_ entries: [LastPerformedEntry]) throws {
        if failsIngest { throw BackfillIngestFailure() }
        ingestedSources.append(contentsOf: entries.map(\.source))
    }

    func entryCount(baseName: String) -> Int { 0 }

    func lastPerformedBackfillDidProgress(_ progress: LastPerformedBackfillProgress) {}

    func lastPerformedBackfillDidFinish() {
        didFinish = true
        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting { continuation.resume() }
    }

    func waitForFinish() async {
        if didFinish { return }
        await withCheckedContinuation { continuations.append($0) }
    }
}

@MainActor
private func makeBackfillContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        LastPerformedEntry.self,
        HistoryFillCursor.self,
        configurations: ModelConfiguration(
            "backfill-halt-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

private func pendingSquatGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "C13": "5/1/2026",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8"
        ],
        rows: 20,
        cols: 60
    )
}

private func loggedSquatHistoryGrid(log: String, date: String) -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "C13": date,
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8",
            "K15": log
        ],
        rows: 20,
        cols: 60
    )
}

/// A non-transient error is never retried, so the fill halts at that tab instead of skipping it —
/// the same rule the transient-budget halt follows, reached by the other arm.
@MainActor
@Test func nonTransientHistoricalTabErrorHaltsTheBackfillBeforeTheDeeperTab() async throws {
    let container = try makeBackfillContainer()
    let client = HaltingBackfillClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": pendingSquatGrid(),
            "Block 26": loggedSquatHistoryGrid(log: "245x5@8", date: "4/24/2026"),
            "Block 25": loggedSquatHistoryGrid(log: "235x5@8", date: "4/17/2026")
        ],
        nonTransientFailureTabs: ["Block 26"]
    )
    let probe = BackfillIndexProbe()
    let sync = SyncCoordinator(client: client, context: container.mainContext, lastPerformed: probe)

    await sync.sync(spreadsheetId: "sid")
    await probe.waitForFinish()

    #expect(await client.log.recorded() == ["Block 27", "Block 26"])
    #expect(probe.ingestedSources.isEmpty)
    #expect(sync.state == .idle)
    #expect(try container.mainContext.fetch(FetchDescriptor<HistoryFillCursor>()).isEmpty)
}

/// A tab that reads fine but cannot be stored is reported to the coach, because the halt leaves the
/// coverage count short and the next sync will come straight back to this tab.
@MainActor
@Test func backfillIngestFailureReportsAConflictAndHalts() async throws {
    let container = try makeBackfillContainer()
    let client = HaltingBackfillClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 27": pendingSquatGrid(),
            "Block 26": loggedSquatHistoryGrid(log: "245x5@8", date: "4/24/2026"),
            "Block 25": loggedSquatHistoryGrid(log: "235x5@8", date: "4/17/2026")
        ]
    )
    let probe = BackfillIndexProbe(failsIngest: true)
    let sync = SyncCoordinator(client: client, context: container.mainContext, lastPerformed: probe)

    await sync.sync(spreadsheetId: "sid")
    await probe.waitForFinish()

    #expect(await client.log.recorded() == ["Block 27", "Block 26"])
    #expect(sync.state == .conflict(["Last Performed backfill failed: the index is full"]))
    #expect(try container.mainContext.fetch(FetchDescriptor<HistoryFillCursor>()).isEmpty)
}
