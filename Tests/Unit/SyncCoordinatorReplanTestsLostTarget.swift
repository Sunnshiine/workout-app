import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

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
    ctx.insert(replanPendingWrite(createdAt: 1, column: .lastSetRPE, valueToWrite: "8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, column: .lastSetRPE, valueToWrite: "9", expectedCurrentValue: "7"))
    try ctx.save()
    let client = LiveSheetClient(
        grid: replanGrid(["I14": "Last set RPE", "C15": "Squat", "D15": "1"]),
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
@Test func replanningALastSetRPEWriteAfterTheCoachHidesTheExerciseRowConflictsWithNoTarget() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, setIndex: 1, column: .lastSetRPE, valueToWrite: "8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, setIndex: 1, column: .lastSetRPE, valueToWrite: "9", expectedCurrentValue: "7"))
    try ctx.save()
    let client = LiveSheetClient(
        grid: replanGrid(["I14": "Last set RPE", "C15": "Squat", "D15": "2"]),
        editsLandingBeforeFetch: [2: ["I15": "7"]],
        rowsHiddenBeforeFetch: [2: [15]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("I15") == "7")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .writesRefused(["Squat: Squat was not found in the sheet"]))
    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(remaining.map(\.status) == [.conflict])
    #expect(remaining.map(\.valueToWrite) == ["9"])

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!I15", nil])
    #expect(entries.map(\.finalStatus) == [.succeeded, .conflict])
    #expect(entries.last?.rowScanDetails == "No row selected: Squat was not found in Week 1, Day 1.")
}

@MainActor
@Test func replanningAfterTheCoachClearsTheDayTwoHeaderConflictsWithNoTarget() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, day: 2, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, day: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = LiveSheetClient(
        grid: replanGrid([
            "T14": "Sets", "V14": "Reps", "X14": "Load", "AA14": "Notes",
            "C15": "Squat", "D15": "1",
            "S15": "Squat", "T15": "1"
        ]),
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
