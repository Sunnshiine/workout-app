import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private final class BatchFlushStubClient: SheetsClient, @unchecked Sendable {
    var grid: SheetGrid
    var rowVisibility: [Int: SheetRowVisibility]
    var fetches: [String] = []
    var attemptedRanges: [String] = []
    var updates: [(String, [[String]])] = []
    var updateRequestCount = 0
    var failedUpdateRequestNumbers: Set<Int> = []

    init(grid: SheetGrid, rowVisibility: [Int: SheetRowVisibility] = [:]) {
        self.grid = grid
        self.rowVisibility = rowVisibility
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        fetches.append(tabName)
        return SheetSnapshot(values: grid, rowVisibility: rowVisibility)
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        updateRequestCount += 1
        attemptedRanges.append(range)
        if failedUpdateRequestNumbers.contains(updateRequestCount) {
            throw URLError(.cannotConnectToHost)
        }
        updates.append((range, values))
        apply(range: range, values: values)
    }

    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
        updateRequestCount += 1
        attemptedRanges.append(contentsOf: updates.map(\.range))
        if failedUpdateRequestNumbers.contains(updateRequestCount) {
            throw URLError(.cannotConnectToHost)
        }
        self.updates.append(contentsOf: updates.map { ($0.range, $0.values) })
        for update in updates {
            apply(range: update.range, values: update.values)
        }
    }

    private func apply(range: String, values: [[String]]) {
        guard
            let reference = range.split(separator: "!").last,
            let value = values.first?.first
        else { return }

        let target = a1ToIndex(String(reference))
        if target.row >= grid.count {
            grid.append(contentsOf: SheetGrid(repeating: [], count: target.row - grid.count + 1))
        }
        if target.col >= grid[target.row].count {
            grid[target.row].append(contentsOf: [String](repeating: "", count: target.col - grid[target.row].count + 1))
        }
        grid[target.row][target.col] = value
    }
}

@MainActor
private func makeBatchContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        WriteTargetAuditEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func batchPendingWrite(
    createdAt: TimeInterval,
    exerciseName: String = "Squat",
    setIndex: Int = 0,
    column: PendingWriteColumn = .notes,
    operation: PendingWriteOperation = .upsert,
    valueToWrite: String? = "185x5@8",
    expectedCurrentValue: String = ""
) -> PendingWrite {
    PendingWrite(
        createdAt: Date(timeIntervalSince1970: createdAt),
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: exerciseName,
        setIndex: setIndex,
        column: column,
        operation: operation,
        valueToWrite: valueToWrite,
        expectedCurrentValue: expectedCurrentValue
    )
}

@MainActor
@Test func flushAggregatesCompactMultiSetLogsIntoHeaderNotes() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(
        batchPendingWrite(
            createdAt: 1,
            exerciseName: "0:2:0 Hamstring Curl",
            setIndex: 0,
            valueToWrite: "100x10@6"
        )
    )
    ctx.insert(
        batchPendingWrite(
            createdAt: 2,
            exerciseName: "0:2:0 Hamstring Curl",
            setIndex: 1,
            valueToWrite: "100x10@6"
        )
    )
    ctx.insert(
        batchPendingWrite(
            createdAt: 3,
            exerciseName: "0:2:0 Hamstring Curl",
            setIndex: 1,
            column: .lastSetRPE,
            valueToWrite: "6"
        )
    )
    try ctx.save()
    let client = BatchFlushStubClient(grid: compactHamstringCurlGrid())
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updateRequestCount == 2)
    #expect(client.updates.map(\.0) == ["'Block 27'!K30", "'Block 27'!K30", "'Block 27'!I30"])
    #expect(client.updates.map(\.1) == [[["100x10@6"]], [["100x10@6, 100x10@6"]], [["6"]]])
    #expect(client.grid.cell(row: 29, col: 10) == "100x10@6, 100x10@6")
    #expect(client.grid.cell(row: 30, col: 10) == "")
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.state == .idle)
}

@MainActor
@Test func successfulFlushRecordsWriteTargetAuditEntry() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, setIndex: 0, valueToWrite: "185x5@8"))
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: coachNoteHiddenContinuationGrid(),
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    let entry = try #require(entries.first)
    #expect(entries.count == 1)
    #expect(entry.blockTab == "Block 27")
    #expect(entry.week == 1)
    #expect(entry.day == 1)
    #expect(entry.exerciseName == "Squat")
    #expect(entry.setIndex == 0)
    #expect(entry.column == .notes)
    #expect(entry.selectedA1Target == "'Block 27'!K17")
    #expect(entry.rowScanDetails.contains("Skipped hidden rows: row 16 hidden by user"))
    #expect(entry.rowScanDetails.contains("Selected row 17"))
    #expect(entry.valueCheckOutcome.contains("matched expected"))
    #expect(entry.finalStatus == .succeeded)
}

@MainActor
@Test func conflictFlushRecordsWriteTargetAuditEntryWhenNoWritableRowIsSelected() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, exerciseName: "Bench Press", valueToWrite: "135x5@7"))
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: multiExerciseConflictGrid(),
        rowVisibility: [17: SheetRowVisibility(hiddenByUser: true)]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    let entry = try #require(entries.first)
    #expect(entries.count == 1)
    #expect(entry.exerciseName == "Bench Press")
    #expect(entry.selectedA1Target == nil)
    #expect(entry.rowScanDetails.contains("Skipped hidden rows: row 18 hidden by user"))
    #expect(entry.rowScanDetails.contains("No row selected"))
    #expect(entry.valueCheckOutcome == "Not checked because no target was selected.")
    #expect(entry.finalStatus == .conflict)
}

@MainActor
@Test func selectedTargetConflictRecordsWriterReportedValueCheck() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, setIndex: 1, valueToWrite: "195x5@9"))
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: coachNoteHiddenContinuationGrid(firstVisibleLog: "coach edited"),
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>())
    let entry = try #require(entries.first)
    #expect(entries.count == 1)
    #expect(entry.selectedA1Target == "'Block 27'!K17")
    #expect(entry.currentValue == "coach edited")
    #expect(entry.valueCheckOutcome == "Expected '', found 'coach edited'.")
    #expect(entry.finalStatus == .conflict)
}

@MainActor
@Test func writeTargetAuditLogKeepsMostRecentOneHundredEntries() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    for index in 0..<100 {
        ctx.insert(
            WriteTargetAuditEntry(
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                blockTab: "Block 27",
                week: 1,
                day: 1,
                exerciseName: "Old \(index)",
                setIndex: 0,
                column: .notes,
                selectedA1Target: nil,
                rowScanDetails: "old",
                expectedCurrentValue: "",
                currentValue: nil,
                valueCheckOutcome: "old",
                finalStatus: .succeeded,
                message: nil
            )
        )
    }
    ctx.insert(batchPendingWrite(createdAt: 101, valueToWrite: "185x5@8"))
    try ctx.save()
    let client = BatchFlushStubClient(grid: oneSetGrid())
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let entries = try ctx.fetch(
        FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)])
    )
    #expect(entries.count == 100)
    #expect(entries.first?.exerciseName == "Old 1")
    #expect(entries.last?.exerciseName == "Squat")
}

@MainActor
@Test func flushBatchesIndependentNonOverlappingPendingWrites() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, setIndex: 0, valueToWrite: "185x5@8"))
    ctx.insert(batchPendingWrite(createdAt: 2, setIndex: 1, column: .lastSetRPE, valueToWrite: "8"))
    try ctx.save()
    let client = BatchFlushStubClient(grid: twoSetGrid())
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.fetches == ["Block 27"])
    #expect(client.updateRequestCount == 1)
    #expect(client.updates.map(\.0) == ["'Block 27'!K15", "'Block 27'!I15"])
    #expect(client.updates.map(\.1) == [[["185x5@8"]], [["8"]]])
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.state == .idle)
}

@MainActor
@Test func flushSplitsOverlappingTargetRangesIntoOrderedBatches() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, valueToWrite: "185x5@8"))
    ctx.insert(batchPendingWrite(createdAt: 2, valueToWrite: "185x6@8", expectedCurrentValue: "185x5@8"))
    try ctx.save()
    let client = BatchFlushStubClient(grid: oneSetGrid())
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updateRequestCount == 2)
    #expect(client.updates.map(\.0) == ["'Block 27'!K15", "'Block 27'!K15"])
    #expect(client.updates.map(\.1) == [[["185x5@8"]], [["185x6@8"]]])
    #expect(client.grid.cell(row: 14, col: 10) == "185x6@8")
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.state == .idle)
}

@MainActor
@Test func flushSplitsExpectedCurrentValueDependenciesIntoOrderedBatches() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, valueToWrite: "185x5@8"))
    ctx.insert(
        batchPendingWrite(
            createdAt: 2,
            operation: .delete,
            valueToWrite: nil,
            expectedCurrentValue: "185x5@8"
        )
    )
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: coachNoteHiddenContinuationGrid(),
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updateRequestCount == 2)
    #expect(client.updates.map(\.0) == ["'Block 27'!K17", "'Block 27'!K17"])
    #expect(client.updates.map(\.1) == [[["185x5@8"]], [[""]]])
    #expect(client.grid.cell(row: 15, col: 10) == "")
    #expect(client.grid.cell(row: 16, col: 10) == "")
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
}

@MainActor
@Test func flushExcludesConflictsFromBatchWithoutBlockingCompatibleWrites() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, exerciseName: "Squat", valueToWrite: "185x5@8"))
    ctx.insert(batchPendingWrite(createdAt: 2, exerciseName: "Bench Press", valueToWrite: "135x5@7"))
    ctx.insert(batchPendingWrite(createdAt: 3, exerciseName: "Deadlift", valueToWrite: "275x5@8"))
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: multiExerciseConflictGrid(),
        rowVisibility: [17: SheetRowVisibility(hiddenByUser: true)]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updateRequestCount == 1)
    #expect(client.updates.map(\.0) == ["'Block 27'!K15", "'Block 27'!K19"])
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.count == 1)
    let conflict = try #require(writes.first)
    #expect(conflict.exerciseName == "Bench Press")
    #expect(conflict.status == .conflict)
    #expect(isConflict(sync.state))
}

@MainActor
@Test func missingFinalSetContinuationRowDoesNotWriteLastSetRPE() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, setIndex: 0, valueToWrite: "185x5@8"))
    ctx.insert(batchPendingWrite(createdAt: 2, setIndex: 0, column: .lastSetRPE, valueToWrite: "8"))
    try ctx.save()
    let client = BatchFlushStubClient(grid: missingContinuationRowGrid())
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(client.updates.isEmpty)
    #expect(writes.count == 2)
    #expect(writes.allSatisfy { $0.status == .conflict })
    let messages = try #require(conflictMessages(sync.state))
    #expect(
        messages.contains {
            $0.contains("Squat") && $0.contains("Set 1") && $0.contains("existing header Notes")
        }
    )
}

@MainActor
@Test func compactSetConflictExplainsHeaderNotesBlockSafeFallbackRow() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(
        batchPendingWrite(
            createdAt: 1,
            exerciseName: "0:2:0 Hip Thrust of Choice",
            setIndex: 1,
            valueToWrite: "135x8@8"
        )
    )
    try ctx.save()
    let client = BatchFlushStubClient(grid: hipThrustHeaderNotesConflictGrid())
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let write = try #require(try ctx.fetch(FetchDescriptor<PendingWrite>()).first)
    let messages = try #require(conflictMessages(sync.state))
    let message = try #require(messages.first)
    #expect(client.updates.isEmpty)
    #expect(write.status == .conflict)
    #expect(message.contains("0:2:0 Hip Thrust of Choice"))
    #expect(message.contains("Set 2"))
    #expect(message.contains("existing header Notes"))
    #expect(message.contains("no safe Set row"))
    #expect(message.contains("Add a row in the Sheet"))
}

@MainActor
@Test func failedBatchLeavesIncludedPendingWritesForRetry() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, setIndex: 0, valueToWrite: "185x5@8"))
    ctx.insert(batchPendingWrite(createdAt: 2, setIndex: 1, valueToWrite: "195x5@8"))
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: coachNoteHiddenContinuationGrid(),
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )
    client.failedUpdateRequestNumbers = [1]
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(client.updateRequestCount == 1)
    #expect(client.attemptedRanges == ["'Block 27'!K17"])
    #expect(writes.count == 2)
    #expect(writes.allSatisfy { $0.status == .pending })
    #expect(writes.map(\.retryCount).sorted() == [0, 1])
    #expect(client.grid.cell(row: 15, col: 10) == "")
    #expect(client.grid.cell(row: 16, col: 10) == "")
}

@MainActor
@Test func failedFinalSetBatchDoesNotWriteLastSetRPE() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, setIndex: 1, valueToWrite: "195x5@9"))
    ctx.insert(batchPendingWrite(createdAt: 2, setIndex: 1, column: .lastSetRPE, valueToWrite: "9"))
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: coachNoteHiddenContinuationGrid(firstVisibleLog: "185x5@8", includesLastSetRPE: true),
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )
    client.failedUpdateRequestNumbers = [1]
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(client.updateRequestCount == 1)
    #expect(client.attemptedRanges == ["'Block 27'!K17", "'Block 27'!I15"])
    #expect(client.updates.isEmpty)
    #expect(client.grid.cell(row: 15, col: 10) == "")
    #expect(client.grid.cell(row: 16, col: 10) == "185x5@8")
    #expect(client.grid.cell(row: 14, col: 8) == "")
    #expect(writes.count == 2)
    #expect(writes.allSatisfy { $0.status == .pending && $0.retryCount == 1 })
}

@MainActor
@Test func successfulBatchDeletesOnlyWritesIncludedInThatBatch() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, valueToWrite: "185x5@8"))
    ctx.insert(batchPendingWrite(createdAt: 2, valueToWrite: "185x6@8", expectedCurrentValue: "185x5@8"))
    try ctx.save()
    let client = BatchFlushStubClient(grid: oneSetGrid())
    client.failedUpdateRequestNumbers = [2]
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(client.updateRequestCount == 2)
    #expect(client.grid.cell(row: 14, col: 10) == "185x5@8")
    #expect(remaining.count == 1)
    let retry = try #require(remaining.first)
    #expect(retry.valueToWrite == "185x6@8")
    #expect(retry.status == .pending)
    #expect(retry.retryCount == 1)
}

@MainActor
@Test func flushBatchesFinalSetNotesAndLastSetRPEWrites() async throws {
    let container = try makeBatchContainer()
    let ctx = container.mainContext
    ctx.insert(batchPendingWrite(createdAt: 1, setIndex: 0, valueToWrite: "185x5@8"))
    ctx.insert(batchPendingWrite(createdAt: 2, setIndex: 1, valueToWrite: "195x5@9"))
    ctx.insert(batchPendingWrite(createdAt: 3, setIndex: 1, column: .lastSetRPE, valueToWrite: "9"))
    try ctx.save()
    let client = BatchFlushStubClient(
        grid: coachNoteHiddenContinuationGrid(includesLastSetRPE: true),
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.fetches == ["Block 27"])
    #expect(client.updateRequestCount == 2)
    #expect(client.updates.map(\.0) == ["'Block 27'!K17", "'Block 27'!K17", "'Block 27'!I15"])
    #expect(client.updates.map(\.1) == [[["185x5@8"]], [["185x5@8, 195x5@9"]], [["9"]]])
    #expect(client.grid.cell(row: 15, col: 10) == "")
    #expect(client.grid.cell(row: 16, col: 10) == "185x5@8, 195x5@9")
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
}

private func oneSetGrid() -> SheetGrid {
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

private func twoSetGrid(notesOnly: Bool = false, firstSetLog: String? = nil) -> SheetGrid {
    var cells = [
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
        "C15": "Squat", "D15": "2"
    ]
    if let firstSetLog {
        cells["K15"] = firstSetLog
    }
    if !notesOnly {
        cells["I14"] = "Last set RPE"
    }
    return gridFromA1(cells, rows: 24, cols: 30)
}

private func coachNoteHiddenContinuationGrid(firstVisibleLog: String? = nil, includesLastSetRPE: Bool = false) -> SheetGrid {
    var cells = [
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
        "C15": "Squat", "D15": "2", "K15": "Coach note",
        "C19": "Bench Press", "D19": "1"
    ]
    if let firstVisibleLog {
        cells["K17"] = firstVisibleLog
    }
    if includesLastSetRPE {
        cells["I14"] = "Last set RPE"
    }
    return gridFromA1(cells, rows: 24, cols: 30)
}

private func compactHamstringCurlGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C30": "0:2:0 Hamstring Curl", "D30": "2", "F30": "10", "H30": "RPE7, RF",
            "C32": "0:1:0 Lateral Neck Flexion", "D32": "2"
        ],
        rows: 36,
        cols: 30
    )
}

private func multiExerciseConflictGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1",
            "C17": "Bench Press", "D17": "1", "K17": "Coach note",
            "C19": "Deadlift", "D19": "1"
        ],
        rows: 28,
        cols: 30
    )
}

private func missingContinuationRowGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "1", "K15": "Coach note",
            "C16": "Bench Press", "D16": "1"
        ],
        rows: 24,
        cols: 30
    )
}

private func hipThrustHeaderNotesConflictGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load",
            "I14": "Last set RPE", "K14": "Notes",
            "C15": "0:2:0 Hip Thrust of Choice", "D15": "2",
            "K15": "70@10, 55; keep hips tucked",
            "C16": "Bench Press", "D16": "1"
        ],
        rows: 24,
        cols: 30
    )
}

private func isConflict(_ state: SyncCoordinator.State) -> Bool {
    if case .conflict = state { return true }
    return false
}

private func conflictMessages(_ state: SyncCoordinator.State) -> [String]? {
    if case .conflict(let messages) = state { return messages }
    return nil
}
