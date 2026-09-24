import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private final class LiveSheetClient: SheetsClient, @unchecked Sendable {
    private var grid: SheetGrid
    private let editsLandingBeforeFetch: [Int: [String: String]]
    private let rowsHiddenBeforeFetch: [Int: [Int]]
    private var rowVisibility: [Int: SheetRowVisibility] = [:]
    private(set) var fetchCount = 0
    private(set) var updateRequestCount = 0

    init(
        grid: SheetGrid,
        editsLandingBeforeFetch: [Int: [String: String]] = [:],
        rowsHiddenBeforeFetch: [Int: [Int]] = [:]
    ) {
        self.grid = grid
        self.editsLandingBeforeFetch = editsLandingBeforeFetch
        self.rowsHiddenBeforeFetch = rowsHiddenBeforeFetch
    }

    func cell(_ a1: String) -> String {
        let index = a1CellIndex(a1)!
        return grid.cell(row: index.row, col: index.col)
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        fetchCount += 1
        for (a1, value) in editsLandingBeforeFetch[fetchCount] ?? [:] {
            write([[value]], to: a1)
        }
        for row in rowsHiddenBeforeFetch[fetchCount] ?? [] {
            rowVisibility[row - 1] = SheetRowVisibility(hiddenByUser: true)
        }
        return SheetSnapshot(values: grid, rowVisibility: rowVisibility)
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        write(values, to: splitA1Range(range)!.reference)
    }

    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
        updateRequestCount += 1
        for update in updates {
            try await updateCells(spreadsheetId: spreadsheetId, range: update.range, values: update.values)
        }
    }

    private func write(_ values: [[String]], to a1: String) {
        let index = a1CellIndex(a1)!
        grid.write(values, atRow: index.row, col: index.col)
    }
}

@MainActor
private func makeReplanContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func replanPendingWrite(
    createdAt: TimeInterval,
    valueToWrite: String,
    expectedCurrentValue: String
) -> PendingWrite {
    PendingWrite(
        createdAt: Date(timeIntervalSince1970: createdAt),
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: valueToWrite,
        expectedCurrentValue: expectedCurrentValue
    )
}

private func squatOneSetGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1"
        ],
        rows: 24,
        cols: 30
    )
}

/// Both Notes writes resolve to K15, so the second one is planned against a batch that already
/// holds that cell, and the coach's edit is what the second write expects.
///
/// #750's C03 to C05 (three Sets in one list cell, the other tokens kept) have no case here. Their
/// target never moves, so the re-plan reaches the token merge only through the same
/// `PlannedPendingWrite(write, against: refetched, ...)` this test drives, and
/// `correctsUnstructuredSetLogInCompactListOnCoachNoteRedirectedRow` pins that merge.
@MainActor
@Test func replanningAnAlreadyBatchedTargetReadsTheSheetAgainAndLandsTheWrite() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    let coachEdit = "205x3@9"
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: coachEdit))
    try ctx.save()
    let client = LiveSheetClient(grid: squatOneSetGrid(), editsLandingBeforeFetch: [2: ["K15": coachEdit]])
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K15") == "205x3@10")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .clear)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    #expect(entries.map(\.finalStatus) == [.succeeded, .succeeded])
    #expect(entries.allSatisfy { $0.selectedA1Target == "'Block 27'!K15" })
}

@MainActor
@Test func replanningAnAlreadyBatchedTargetConflictsAgainstTheValueTheSheetReallyHolds() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = LiveSheetClient(grid: squatOneSetGrid(), editsLandingBeforeFetch: [2: ["K15": "300x1@10"]])
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K15") == "300x1@10")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .writesRefused(["Squat: Expected '205x3@9', found '300x1@10'"]))

    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(remaining.count == 1)
    #expect(remaining.first?.status == .conflict)
    #expect(remaining.first?.valueToWrite == "205x3@10")

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    #expect(entries.map(\.finalStatus).sorted { $0.rawValue < $1.rawValue } == [.conflict, .succeeded])
    let conflictEntry = try #require(entries.first { $0.finalStatus == .conflict })
    #expect(conflictEntry.selectedA1Target == "'Block 27'!K15")
    #expect(conflictEntry.currentValue == "300x1@10")
    #expect(conflictEntry.valueCheckOutcome == "Expected '205x3@9', found '300x1@10'.")
}

@MainActor
@Test(arguments: ["185x5@8", "", "185x5@8, 185x5@9"])
func replanningALastSetRPEWriteAfterTheCoachSwapsHeadersWritesTheCellNowHeadedLastSetRPE(
    coachI15: String
) async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    for (createdAt, rpe) in [(1.0, "8"), (2.0, "9")] {
        let write = replanPendingWrite(createdAt: createdAt, valueToWrite: rpe, expectedCurrentValue: "")
        write.column = .lastSetRPE
        write.setIndex = 1
        ctx.insert(write)
    }
    try ctx.save()
    let client = LiveSheetClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
                "C15": "Squat", "D15": "2"
            ],
            rows: 24,
            cols: 30
        ),
        editsLandingBeforeFetch: [2: ["I14": "Notes", "K14": "Last set RPE", "I15": coachI15]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("I15") == coachI15)
    #expect(client.cell("K15") == "9")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .clear)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!I15", "'Block 27'!K15"])
    #expect(entries.map(\.finalStatus) == [.succeeded, .succeeded])
    #expect(entries.last?.rowScanDetails == "Selected row 15: visible Exercise row for Last Set RPE.")
}

@MainActor
@Test func replanningASetLogAfterTheCoachSwapsHeadersConflictsOnTheCellNowHeadedNotes() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = LiveSheetClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
                "C15": "Squat", "D15": "1"
            ],
            rows: 24,
            cols: 30
        ),
        editsLandingBeforeFetch: [2: ["I14": "Notes", "K14": "Last set RPE", "K15": "205x3@9"]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("I15") == "")
    #expect(client.cell("K15") == "205x3@9")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .writesRefused(["Squat: Expected '205x3@9', found ''"]))
    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(remaining.map(\.status) == [.conflict])
    #expect(remaining.map(\.valueToWrite) == ["205x3@10"])

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!K15", "'Block 27'!I15"])
    #expect(entries.map(\.finalStatus) == [.succeeded, .conflict])
    #expect(
        entries.last?.rowScanDetails == "Selected row 15: compact header Notes row stores Set logs as a comma-separated list."
    )
    #expect(entries.last?.valueCheckOutcome == "Expected '205x3@9', found ''.")
}

private func squatCoachNoteGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "K15": "Keep elbows soft"
        ],
        rows: 24,
        cols: 30
    )
}

@MainActor
@Test func replanningAfterTheCoachHidesTheSetRowConflictsOnTheNextVisibleWritableRow() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = LiveSheetClient(
        grid: squatCoachNoteGrid(),
        editsLandingBeforeFetch: [2: ["K16": "205x3@9"]],
        rowsHiddenBeforeFetch: [2: [16]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K16") == "205x3@9")
    #expect(client.cell("K17") == "")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .writesRefused(["Squat: Expected '205x3@9', found ''"]))
    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(remaining.map(\.status) == [.conflict])
    #expect(remaining.map(\.valueToWrite) == ["205x3@10"])

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!K16", "'Block 27'!K17"])
    #expect(entries.map(\.finalStatus) == [.succeeded, .conflict])
    #expect(
        entries.last?.rowScanDetails
            == "Skipped hidden rows: row 16 hidden by user. Selected row 17: first visible writable row below "
            + "protected header Notes before the next Exercise."
    )
    #expect(entries.last?.valueCheckOutcome == "Expected '205x3@9', found ''.")
}

@MainActor
@Test func replanningAfterTheCoachMovesTheSetRowWritesTheRowItMovedTo() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = LiveSheetClient(
        grid: squatCoachNoteGrid(),
        editsLandingBeforeFetch: [2: ["K16": "", "K17": "205x3@9"]],
        rowsHiddenBeforeFetch: [2: [16]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K16") == "")
    #expect(client.cell("K17") == "205x3@10")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .clear)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!K16", "'Block 27'!K17"])
    #expect(entries.map(\.finalStatus) == [.succeeded, .succeeded])
}

@MainActor
@Test func replanningAfterTheCoachHidesEveryRowBelowACoachNoteConflictsWithNoSafeSetRow() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = LiveSheetClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1", "K15": "Keep elbows soft",
                "C18": "Bench Press", "D18": "1"
            ],
            rows: 24,
            cols: 30
        ),
        editsLandingBeforeFetch: [2: ["K16": "205x3@9"]],
        rowsHiddenBeforeFetch: [2: [16, 17]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K16") == "205x3@9")
    #expect(client.cell("K17") == "")
    #expect(client.cell("K18") == "")
    #expect(client.fetchCount == 2)
    #expect(
        sync.outcome
            == .writesRefused([
                "Squat: Set 1 for Squat cannot be written because existing header Notes prevent writing there, and no "
                    + "safe Set row exists before the next Exercise. Add a row in the Sheet, clear or migrate the existing "
                    + "header note, then sync again."
            ])
    )
    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(remaining.map(\.status) == [.conflict])
    #expect(remaining.map(\.valueToWrite) == ["205x3@10"])

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!K16", nil])
    #expect(entries.map(\.finalStatus) == [.succeeded, .conflict])
    #expect(
        entries.last?.rowScanDetails
            == "Skipped hidden rows: row 16 hidden by user, row 17 hidden by user. No row selected: no visible writable "
            + "row below protected header Notes before the next Exercise."
    )
}

@MainActor
@Test func replanningAfterTheCoachHidesEveryRowBelowACoachNoteAlsoRefusesThePairedLastSetRPE() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    let setThree = replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9")
    setThree.setIndex = 2
    ctx.insert(setThree)
    let setThreeRPE = replanPendingWrite(createdAt: 3, valueToWrite: "10", expectedCurrentValue: "")
    setThreeRPE.setIndex = 2
    setThreeRPE.column = .lastSetRPE
    ctx.insert(setThreeRPE)
    try ctx.save()
    let client = LiveSheetClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
                "C15": "Squat", "D15": "3", "K15": "Keep elbows soft",
                "C19": "Bench Press", "D19": "1"
            ],
            rows: 24,
            cols: 30
        ),
        editsLandingBeforeFetch: [2: ["K16": "185x5@8, , 205x3@9"]],
        rowsHiddenBeforeFetch: [2: [16, 17, 18]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let setLogRefusal =
        "Squat: Set 3 for Squat cannot be written because existing header Notes prevent writing there, and no safe "
        + "Set row exists before the next Exercise. Add a row in the Sheet, clear or migrate the existing header "
        + "note, then sync again."
    #expect(client.cell("K16") == "185x5@8, , 205x3@9")
    #expect(client.cell("K17") == "")
    #expect(client.cell("K18") == "")
    #expect(client.cell("K19") == "")
    #expect(client.cell("I15") == "")
    #expect(client.fetchCount == 2)
    #expect(
        sync.outcome
            == .writesRefused([
                setLogRefusal,
                "Squat: Last Set RPE was not written because the paired Set Log failed: " + setLogRefusal
            ])
    )
    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(remaining.map(\.status) == [.conflict, .conflict])
    #expect(remaining.map(\.valueToWrite) == ["205x3@10", "10"])

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!K16", nil, nil])
    #expect(entries.map(\.finalStatus) == [.succeeded, .conflict, .conflict])
    #expect(
        entries.dropFirst().map(\.rowScanDetails) == [
            "Skipped hidden rows: row 16 hidden by user, row 17 hidden by user, row 18 hidden by user. No row "
                + "selected: no visible writable row below protected header Notes before the next Exercise.",
            "Not evaluated: paired Set Log failed before this write was planned."
        ]
    )
}

@MainActor
@Test func replanningAfterTheCoachClearsTheNotesHeaderConflictsWithNoTarget() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = LiveSheetClient(
        grid: squatOneSetGrid(),
        editsLandingBeforeFetch: [2: ["K14": "", "K15": "205x3@9"]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K15") == "205x3@9")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .writesRefused(["Squat: Notes column was not found"]))
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).map(\.status) == [.conflict])

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!K15", nil])
    #expect(entries.map(\.finalStatus) == [.succeeded, .conflict])
    #expect(entries.last?.rowScanDetails == "No row selected: Week 1, Day 1 has no Notes column.")
    #expect(entries.last?.valueCheckOutcome == "Not checked because no target was selected.")
}

@MainActor
@Test func replanningAfterTheCoachClearsTheLastSetRPEHeaderConflictsWithNoTarget() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    for (createdAt, rpe, expected) in [(1.0, "8", ""), (2.0, "9", "7")] {
        let write = replanPendingWrite(createdAt: createdAt, valueToWrite: rpe, expectedCurrentValue: expected)
        write.column = .lastSetRPE
        ctx.insert(write)
    }
    try ctx.save()
    let client = LiveSheetClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
                "C15": "Squat", "D15": "1"
            ],
            rows: 24,
            cols: 30
        ),
        editsLandingBeforeFetch: [2: ["I14": "", "I15": "7"]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("I15") == "7")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .writesRefused(["Squat: Last set RPE column was not found"]))
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).map(\.status) == [.conflict])

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!I15", nil])
    #expect(entries.map(\.finalStatus) == [.succeeded, .conflict])
    #expect(entries.last?.rowScanDetails == "No row selected: Week 1, Day 1 has no Last set RPE column.")
}

@MainActor
@Test func replanningAfterTheCoachRenamesTheExerciseConflictsWithNoTarget() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = LiveSheetClient(
        grid: squatOneSetGrid(),
        editsLandingBeforeFetch: [2: ["C15": "Back Squat", "K15": "205x3@9"]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K15") == "205x3@9")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .writesRefused(["Squat: Squat was not found in the sheet"]))
    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(remaining.map(\.status) == [.conflict])
    #expect(remaining.map(\.valueToWrite) == ["205x3@10"])

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!K15", nil])
    #expect(entries.map(\.finalStatus) == [.succeeded, .conflict])
    #expect(entries.last?.rowScanDetails == "No row selected: Squat was not found in Week 1, Day 1.")
}

@MainActor
@Test func replanningAfterTheCoachDeletesTheDayConflictsWithNoTarget() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    for (createdAt, value, expected) in [(1.0, "185x5@8", ""), (2.0, "205x3@10", "205x3@9")] {
        let write = replanPendingWrite(createdAt: createdAt, valueToWrite: value, expectedCurrentValue: expected)
        write.day = 2
        ctx.insert(write)
    }
    try ctx.save()
    let client = LiveSheetClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "T14": "Sets", "V14": "Reps", "X14": "Load", "AA14": "Notes",
                "C15": "Squat", "D15": "1",
                "S15": "Squat", "T15": "1"
            ],
            rows: 24,
            cols: 30
        ),
        editsLandingBeforeFetch: [2: ["S12": "", "AA15": "205x3@9"]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("AA15") == "205x3@9")
    #expect(client.cell("K15") == "")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .writesRefused(["Squat: Day 2 was not found in the sheet"]))
    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(remaining.map(\.status) == [.conflict])
    #expect(remaining.map(\.valueToWrite) == ["205x3@10"])

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!AA15", nil])
    #expect(entries.map(\.finalStatus) == [.succeeded, .conflict])
    #expect(entries.last?.rowScanDetails == "No row selected: Week 1, Day 2 was not found.")
}

/// The coach inserts a blank row 16, so the second and third Prescription Lines move down one row. The
/// interim flush is one update request and the final batch, holding K17 and K18, is the second.
@MainActor
@Test func replanningAfterTheCoachInsertsARowLandsTheWriteAndTheNextSetInOneBatch() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    for (createdAt, setIndex, value, expected) in [
        (1.0, 1, "185x5@8", ""), (2.0, 1, "205x3@10", "205x3@9"), (3.0, 2, "150x3@7", "")
    ] {
        let write = replanPendingWrite(createdAt: createdAt, valueToWrite: value, expectedCurrentValue: expected)
        write.setIndex = setIndex
        ctx.insert(write)
    }
    try ctx.save()
    let client = LiveSheetClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1", "F15": "5",
                "D16": "1", "F16": "5",
                "D17": "1", "F17": "3",
                "C20": "Bench Press", "D20": "1"
            ],
            rows: 24,
            cols: 30
        ),
        editsLandingBeforeFetch: [
            2: [
                "D16": "", "F16": "", "K16": "",
                "D17": "1", "F17": "5", "K17": "205x3@9",
                "D18": "1", "F18": "3",
                "C20": "", "D20": "", "C21": "Bench Press", "D21": "1"
            ]
        ]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K15") == "")
    #expect(client.cell("K16") == "")
    #expect(client.cell("K17") == "205x3@10")
    #expect(client.cell("K18") == "150x3@7")
    #expect(client.cell("K21") == "")
    #expect(client.fetchCount == 2)
    #expect(client.updateRequestCount == 2)
    #expect(sync.outcome == .clear)
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!K16", "'Block 27'!K17", "'Block 27'!K18"])
    #expect(entries.map(\.finalStatus) == [.succeeded, .succeeded, .succeeded])
    let lineRow = ": Prescription Line row stores this Line's Set logs as a comma-separated list (Set 1 of the Line)."
    #expect(
        entries.map(\.rowScanDetails) == ["Selected row 16" + lineRow, "Selected row 17" + lineRow, "Selected row 18" + lineRow]
    )
}

/// The second write lands on a different Exercise, so nothing overlaps and no re-plan happens.
@MainActor
@Test func planningFailureOnAFreshTargetConflictsWithoutWritingTheBatchEarly() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    let mismatched = replanPendingWrite(createdAt: 2, valueToWrite: "225x3@9", expectedCurrentValue: "205x3@9")
    mismatched.exerciseName = "Bench Press"
    ctx.insert(mismatched)
    try ctx.save()
    let client = LiveSheetClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Squat", "D15": "1",
                "C17": "Bench Press", "D17": "1"
            ],
            rows: 24,
            cols: 30
        )
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K15") == "185x5@8")
    #expect(client.cell("K17") == "")
    #expect(client.fetchCount == 1)
    #expect(sync.outcome == .writesRefused(["Bench Press: Expected '205x3@9', found ''"]))
}
