import Foundation
import Observation
import SwiftData
import Testing

@testable import WorkoutTracker

// MARK: - Fixtures

@MainActor
private func makeHistoryFillContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        LastPerformedEntry.self,
        HistoryFillCursor.self,
        configurations: ModelConfiguration(
            "exercise-history-fill-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

/// A backoff with no real sleeps, so tests exercise the 429 → `.failed` path instantly. Its
/// one-entry schedule means a throttled tab is fetched twice before the run halts.
private func instantBackoff() -> SheetsBackoff {
    SheetsBackoff(schedule: [.zero], sleep: { _ in })
}

@MainActor
private func historyFillCursor(in context: ModelContext, spreadsheetId: String) -> HistoryFillCursor? {
    let descriptor = FetchDescriptor<HistoryFillCursor>(
        predicate: #Predicate { $0.spreadsheetId == spreadsheetId }
    )
    return try? context.fetch(descriptor).first
}

private func squatRequest(titles: [String], baseNames: Set<String> = ["Squat"]) -> ExerciseHistoryFill.Request {
    ExerciseHistoryFill.Request(
        spreadsheetId: "sid",
        tabTitles: titles,
        currentTab: "Block 27",
        baseNames: baseNames
    )
}

private func squatEntry(week: Int) -> LastPerformedEntry {
    LastPerformedEntry(
        fullName: "Squat",
        baseName: "Squat",
        resultText: "24\(week)x5@8",
        performedOn: Date(timeIntervalSince1970: TimeInterval(week)),
        source: "Block 2\(week) · W1 D1"
    )
}

/// Observation calls `onChange` before the write lands, so each call reads the value being
/// replaced: the run's ticks are what it recorded once the leading `nil` is dropped.
@MainActor
private final class ProgressTicks {
    private(set) var recorded: [ExerciseHistoryFill.Progress?] = []

    var ticks: [ExerciseHistoryFill.Progress] { recorded.compactMap { $0 } }

    init(watching fill: ExerciseHistoryFill) {
        observe(fill)
    }

    private func observe(_ fill: ExerciseHistoryFill) {
        withObservationTracking {
            _ = fill.progress
        } onChange: {
            MainActor.assumeIsolated {
                self.recorded.append(fill.progress)
                self.observe(fill)
            }
        }
    }
}

// MARK: - Traversal

@MainActor
@Test func fillReadsEveryHistoricalTabWhenCoverageIsNeverReached() async throws {
    let container = try makeHistoryFillContainer()
    let client = HistoryFillStubClient(
        titles: ["Intro", "Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
        ]
    )
    let index = LastPerformedLookupStore(context: container.mainContext)
    let fill = ExerciseHistoryFill(client: client, context: container.mainContext, index: index)

    let outcome = await fill.run(squatRequest(titles: client.titles))

    // Only two historical tabs exist, so the coverage target is never reached; the fill reads them
    // newest-first and stops on exhaustion.
    #expect(outcome == .tabsExhausted(tabsIngested: 2))
    #expect(await client.recorder.tabs() == ["Block 26", "Block 25"])
    #expect(index.entryCount(baseName: "Squat") == 2)
    #expect(index.snapshot.lookup(for: "Squat")?.resultText == "245x5@8")
    #expect(index.snapshot.lookup(for: "Squat")?.sourceText == "Block 26 · W1 D1")
    #expect(historyFillCursor(in: container.mainContext, spreadsheetId: "sid") == nil)
}

@MainActor
@Test func fillStopsWhenEveryBaseNameReachesTheSheetsEntryLimit() async throws {
    let container = try makeHistoryFillContainer()
    let client = HistoryFillStubClient(
        titles: ["Block 22", "Block 23", "Block 24", "Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026"),
            "Block 24": historicalGrid(exerciseName: "Squat", log: "225x5@8", date: "4/10/2026"),
            "Block 23": historicalGrid(exerciseName: "Squat", log: "215x5@8", date: "4/3/2026"),
            "Block 22": historicalGrid(exerciseName: "Squat", log: "205x5@8", date: "3/27/2026")
        ]
    )
    let index = LastPerformedLookupStore(context: container.mainContext)
    // The current Block's own Squat entry, as sync ingests it before starting the fill.
    try index.ingest([squatEntry(week: 7)])
    let fill = ExerciseHistoryFill(client: client, context: container.mainContext, index: index)

    let outcome = await fill.run(squatRequest(titles: client.titles))

    // Five entries is what the sheet shows, so the fifth one stops the run: Block 22 is never read.
    #expect(outcome == .coverageReached(tabsIngested: 4))
    #expect(await client.recorder.tabs() == ["Block 26", "Block 25", "Block 24", "Block 23"])
    #expect(index.entryCount(baseName: "Squat") == 5)
    #expect(historyFillCursor(in: container.mainContext, spreadsheetId: "sid") == nil)
}

@MainActor
@Test func fillReadsNothingWhenCoverageAlreadyHoldsAndClearsAStaleCursor() async throws {
    let container = try makeHistoryFillContainer()
    let index = LastPerformedLookupStore(context: container.mainContext)
    try index.ingest((1...5).map(squatEntry(week:)))
    container.mainContext.insert(HistoryFillCursor(spreadsheetId: "sid", deepestIngestedTab: "Block 26"))
    try container.mainContext.save()
    let client = HistoryFillStubClient(
        titles: ["Intro", "Block 26", "Block 27"],
        grids: ["Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026")]
    )
    let fill = ExerciseHistoryFill(client: client, context: container.mainContext, index: index)

    let outcome = await fill.run(squatRequest(titles: client.titles))

    #expect(outcome == .coverageReached(tabsIngested: 0))
    #expect(await client.recorder.tabs() == [])
    #expect(historyFillCursor(in: container.mainContext, spreadsheetId: "sid") == nil)
}

@MainActor
@Test func repeatedRunsDoNotDuplicateIngestedEntries() async throws {
    let container = try makeHistoryFillContainer()
    let client = HistoryFillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
        ]
    )
    let index = LastPerformedLookupStore(context: container.mainContext)
    let fill = ExerciseHistoryFill(client: client, context: container.mainContext, index: index)

    let first = await fill.run(squatRequest(titles: client.titles))
    let second = await fill.run(squatRequest(titles: client.titles))

    // Coverage is never reached, so both runs read the same tabs; (fullName, source) dedup keeps
    // the entry count at exactly the two distinct Sessions.
    #expect(first == .tabsExhausted(tabsIngested: 2))
    #expect(second == .tabsExhausted(tabsIngested: 2))
    #expect(await client.recorder.tabs() == ["Block 26", "Block 25", "Block 26", "Block 25"])
    #expect(index.entryCount(baseName: "Squat") == 2)
}

@MainActor
@Test func fillDoesNothingWithoutHistoricalTabs() async throws {
    let container = try makeHistoryFillContainer()
    container.mainContext.insert(HistoryFillCursor(spreadsheetId: "sid", deepestIngestedTab: "Block 26"))
    try container.mainContext.save()
    let client = HistoryFillStubClient(titles: ["Intro", "Block 27"], grids: [:])
    let fill = ExerciseHistoryFill(
        client: client,
        context: container.mainContext,
        index: LastPerformedLookupStore(context: container.mainContext)
    )

    let outcome = await fill.run(squatRequest(titles: client.titles))

    #expect(outcome == .nothingToScan)
    #expect(await client.recorder.tabs() == [])
    #expect(historyFillCursor(in: container.mainContext, spreadsheetId: "sid")?.deepestIngestedTab == "Block 26")
}

@MainActor
@Test func fillDoesNothingWhenTheCurrentBlockHasNoExercises() async throws {
    let container = try makeHistoryFillContainer()
    container.mainContext.insert(HistoryFillCursor(spreadsheetId: "sid", deepestIngestedTab: "Block 26"))
    try container.mainContext.save()
    let client = HistoryFillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: ["Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026")]
    )
    let fill = ExerciseHistoryFill(
        client: client,
        context: container.mainContext,
        index: LastPerformedLookupStore(context: container.mainContext)
    )

    let outcome = await fill.run(squatRequest(titles: client.titles, baseNames: []))

    #expect(outcome == .nothingToScan)
    #expect(await client.recorder.tabs() == [])
    #expect(historyFillCursor(in: container.mainContext, spreadsheetId: "sid")?.deepestIngestedTab == "Block 26")
}

// MARK: - Halting

@MainActor
@Test func fillHaltsOnAThrottledTabRatherThanSkippingIt() async throws {
    let container = try makeHistoryFillContainer()
    let client = HistoryFillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
        ],
        transientFailureTabs: ["Block 26"]
    )
    let index = LastPerformedLookupStore(context: container.mainContext)
    let fill = ExerciseHistoryFill(
        client: client,
        context: container.mainContext,
        index: index,
        backoff: instantBackoff()
    )

    let outcome = await fill.run(squatRequest(titles: client.titles))

    #expect(outcome == .halted(tab: "Block 26", reason: .retriesExhausted, tabsIngested: 0))
    #expect(await client.recorder.tabs() == ["Block 26", "Block 26"])
    #expect(index.entryCount(baseName: "Squat") == 0)
    #expect(historyFillCursor(in: container.mainContext, spreadsheetId: "sid") == nil)
}

/// A non-transient error is never retried, so the fill halts at that tab instead of skipping it —
/// the same rule the throttled tab follows, reached by the other arm.
@MainActor
@Test func unreadableTabHaltsTheFillBeforeTheDeeperTab() async throws {
    let container = try makeHistoryFillContainer()
    let client = HistoryFillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
        ],
        unreadableTabs: ["Block 26"]
    )
    let index = LastPerformedLookupStore(context: container.mainContext)
    let fill = ExerciseHistoryFill(client: client, context: container.mainContext, index: index)

    let outcome = await fill.run(squatRequest(titles: client.titles))

    #expect(outcome == .halted(tab: "Block 26", reason: .unreadable, tabsIngested: 0))
    #expect(await client.recorder.tabs() == ["Block 26"])
    #expect(index.entryCount(baseName: "Squat") == 0)
    #expect(historyFillCursor(in: container.mainContext, spreadsheetId: "sid") == nil)
}

@MainActor
@Test func indexRefusalHaltsTheFillAndNamesTheFailure() async throws {
    let container = try makeHistoryFillContainer()
    let client = HistoryFillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
        ]
    )
    let fill = ExerciseHistoryFill(client: client, context: container.mainContext, index: RefusingIndex())

    let outcome = await fill.run(squatRequest(titles: client.titles))

    #expect(outcome == .halted(tab: "Block 26", reason: .indexRejected("the index is full"), tabsIngested: 0))
    #expect(await client.recorder.tabs() == ["Block 26"])
    #expect(historyFillCursor(in: container.mainContext, spreadsheetId: "sid") == nil)
}

// MARK: - Cursor and progress

@MainActor
@Test func haltedFillResumesFromItsCursorOnTheNextRun() async throws {
    let container = try makeHistoryFillContainer()
    let titles = ["Block 24", "Block 25", "Block 26", "Block 27"]
    let grids = [
        "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
        "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026"),
        "Block 24": historicalGrid(exerciseName: "Squat", log: "225x5@8", date: "4/10/2026")
    ]
    let index = LastPerformedLookupStore(context: container.mainContext)
    let firstClient = HistoryFillStubClient(titles: titles, grids: grids, transientFailureTabs: ["Block 25"])
    let first = ExerciseHistoryFill(
        client: firstClient,
        context: container.mainContext,
        index: index,
        backoff: instantBackoff()
    )
    let firstTicks = ProgressTicks(watching: first)

    let firstOutcome = await first.run(squatRequest(titles: titles))

    #expect(firstOutcome == .halted(tab: "Block 25", reason: .retriesExhausted, tabsIngested: 1))
    #expect(await firstClient.recorder.tabs() == ["Block 26", "Block 25", "Block 25"])
    #expect(index.entryCount(baseName: "Squat") == 1)
    #expect(firstTicks.ticks == [ExerciseHistoryFill.Progress(tab: "Block 26", tabsCompleted: 1, tabsToScan: 3)])
    #expect(first.progress == nil)
    let cursor = try #require(historyFillCursor(in: container.mainContext, spreadsheetId: "sid"))
    #expect(cursor.deepestIngestedTab == "Block 26")

    // A fresh fill over the same store stands in for an app restart. Block 25 now reads fine, and
    // the run resumes below the cursor rather than re-reading Block 26.
    let secondClient = HistoryFillStubClient(titles: titles, grids: grids)
    let second = ExerciseHistoryFill(
        client: secondClient,
        context: container.mainContext,
        index: index,
        backoff: instantBackoff()
    )
    let secondTicks = ProgressTicks(watching: second)

    let secondOutcome = await second.run(squatRequest(titles: titles))

    #expect(secondOutcome == .tabsExhausted(tabsIngested: 2))
    #expect(await secondClient.recorder.tabs() == ["Block 25", "Block 24"])
    #expect(index.entryCount(baseName: "Squat") == 3)
    #expect(
        secondTicks.ticks == [
            ExerciseHistoryFill.Progress(tab: "Block 25", tabsCompleted: 1, tabsToScan: 2),
            ExerciseHistoryFill.Progress(tab: "Block 24", tabsCompleted: 2, tabsToScan: 2)
        ]
    )
    #expect(second.progress == nil)
    #expect(historyFillCursor(in: container.mainContext, spreadsheetId: "sid") == nil)
}

@MainActor
@Test func fillPublishesOneTickPerIngestedTabThenClearsIt() async throws {
    let container = try makeHistoryFillContainer()
    let client = HistoryFillStubClient(
        titles: ["Block 25", "Block 26", "Block 27"],
        grids: [
            "Block 26": historicalGrid(exerciseName: "Squat", log: "245x5@8", date: "4/24/2026"),
            "Block 25": historicalGrid(exerciseName: "Squat", log: "235x5@8", date: "4/17/2026")
        ]
    )
    let fill = ExerciseHistoryFill(
        client: client,
        context: container.mainContext,
        index: LastPerformedLookupStore(context: container.mainContext)
    )
    let ticks = ProgressTicks(watching: fill)

    let outcome = await fill.run(squatRequest(titles: client.titles))

    #expect(outcome == .tabsExhausted(tabsIngested: 2))
    #expect(
        ticks.ticks == [
            ExerciseHistoryFill.Progress(tab: "Block 26", tabsCompleted: 1, tabsToScan: 2),
            ExerciseHistoryFill.Progress(tab: "Block 25", tabsCompleted: 2, tabsToScan: 2)
        ]
    )
    #expect(fill.progress == nil)
}
