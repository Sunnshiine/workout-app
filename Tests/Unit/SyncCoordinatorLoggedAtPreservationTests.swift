import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private struct TwoDayStubClient: SheetsClient {
    let grid: SheetGrid

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Intro", "Block 27"] }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: grid)
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}

@MainActor
private func makeLoggedAtContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(
            "logged-at-preservation-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@MainActor
private func makeTwoSessionBlock(tabName: String, day1LoggedAt: Date, day2LoggedAt: Date) -> Block {
    let squat = ParsedExercise(
        name: "Squat",
        baseName: "Squat",
        cadence: nil,
        coachNote: nil,
        sets: [
            ParsedSet(
                index: 0,
                prescribedReps: "5",
                prescribedLoad: "RPE8",
                percentOneRM: nil,
                state: .logged,
                setLog: SetLog(weight: .pounds(185), reps: 5, rpe: 8)
            )
        ]
    )
    let block = BlockBuilder.makeBlock(
        from: ParsedBlockModel(
            tabName: tabName,
            weeks: [
                ParsedWeek(
                    number: 1,
                    days: [
                        ParsedSession(dayNumber: 1, date: nil, exercises: [squat]),
                        ParsedSession(dayNumber: 2, date: nil, exercises: [squat])
                    ]
                )
            ]
        )
    )
    for session in block.weeks[0].sessions {
        session.exercises[0].sets[0].loggedAt = session.dayNumber == 1 ? day1LoggedAt : day2LoggedAt
    }
    return block
}

private func twoSessionSquatGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "R12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8", "K15": "185x5@8",
            "S14": "Sets", "V14": "Reps", "X14": "Load", "Z14": "Notes",
            "R15": "Squat", "S15": "1", "V15": "5", "X15": "RPE8", "Z15": "205x3@9"
        ],
        rows: 20,
        cols: 40
    )
}

@MainActor
private func loggedAt(in block: Block, day: Int) throws -> Date? {
    try #require(
        block.weeks.first { $0.number == 1 }?
            .sessions.first { $0.dayNumber == day }?
            .exercises.first { $0.name == "Squat" }?
            .sets.first { $0.index == 0 }
    ).loggedAt
}

/// Two cached Blocks hold the same Week, Day, Exercise and Set index, so the logged-at carried
/// across a Block replacement has to be keyed by the Block tab and the Day as well, not by the
/// Exercise and Set alone.
@MainActor
@Test func replacingABlockCarriesEachSessionsLoggedAtFromTheMatchingBlockTab() async throws {
    let container = try makeLoggedAtContainer()
    let context = container.mainContext
    let currentDay1 = Date(timeIntervalSinceReferenceDate: 1_000)
    let currentDay2 = Date(timeIntervalSinceReferenceDate: 2_000)
    context.insert(
        makeTwoSessionBlock(tabName: "Block 27", day1LoggedAt: currentDay1, day2LoggedAt: currentDay2)
    )
    context.insert(
        makeTwoSessionBlock(
            tabName: "Block 26",
            day1LoggedAt: Date(timeIntervalSinceReferenceDate: 9_000),
            day2LoggedAt: Date(timeIntervalSinceReferenceDate: 9_001)
        )
    )
    try context.save()
    let sync = SyncCoordinator(client: TwoDayStubClient(grid: twoSessionSquatGrid()), context: context)

    await sync.sync(spreadsheetId: "sid")

    let blocks = try context.fetch(FetchDescriptor<Block>())
    #expect(blocks.map(\.tabName) == ["Block 27"])
    let synced = try #require(blocks.first)
    #expect(try loggedAt(in: synced, day: 1) == currentDay1)
    #expect(try loggedAt(in: synced, day: 2) == currentDay2)
}

/// A Set the Sheet no longer reports as logged keeps no stale local timestamp.
@MainActor
@Test func replacingABlockDropsLoggedAtForASetTheSheetNoLongerReportsAsLogged() async throws {
    let container = try makeLoggedAtContainer()
    let context = container.mainContext
    context.insert(
        makeTwoSessionBlock(
            tabName: "Block 27",
            day1LoggedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            day2LoggedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )
    )
    try context.save()
    var grid = twoSessionSquatGrid()
    grid[14][25] = ""
    let sync = SyncCoordinator(client: TwoDayStubClient(grid: grid), context: context)

    await sync.sync(spreadsheetId: "sid")

    let synced = try #require(try context.fetch(FetchDescriptor<Block>()).first)
    #expect(try loggedAt(in: synced, day: 1) == Date(timeIntervalSinceReferenceDate: 1_000))
    #expect(try loggedAt(in: synced, day: 2) == nil)
}
