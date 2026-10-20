import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private func squatCoachNoteGrid() -> SheetGrid {
    replanGrid(["C15": "Squat", "D15": "1", "K15": "Keep elbows soft"])
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
@Test func replanningAfterTheCoachHidesEveryRowBelowACoachNoteConflictsWithNoVisibleWritableRow() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    try ctx.save()
    let client = LiveSheetClient(
        grid: replanGrid(["C15": "Squat", "D15": "1", "K15": "Keep elbows soft", "C18": "Bench Press", "D18": "1"]),
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
@Test(arguments: ["185x5@8, , 205x3@9", "205x3@9"])
func replanningAfterTheCoachHidesEveryRowBelowACoachNoteAlsoRefusesThePairedLastSetRPE(coachK16: String) async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, setIndex: 2, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    ctx.insert(replanPendingWrite(createdAt: 3, setIndex: 2, column: .lastSetRPE, valueToWrite: "10", expectedCurrentValue: ""))
    try ctx.save()
    let client = LiveSheetClient(
        grid: replanGrid([
            "I14": "Last set RPE",
            "C15": "Squat", "D15": "3", "K15": "Keep elbows soft",
            "C19": "Bench Press", "D19": "1"
        ]),
        editsLandingBeforeFetch: [2: ["K16": coachK16]],
        rowsHiddenBeforeFetch: [2: [16, 17, 18]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let setLogRefusal =
        "Squat: Set 3 for Squat cannot be written because existing header Notes prevent writing there, and no safe "
        + "Set row exists before the next Exercise. Add a row in the Sheet, clear or migrate the existing header "
        + "note, then sync again."
    #expect(client.cell("K16") == coachK16)
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
@Test func replanningAfterTheCoachInsertsARowLandsTheWriteAndTheNextSetInOneBatch() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, setIndex: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, setIndex: 1, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    ctx.insert(replanPendingWrite(createdAt: 3, setIndex: 2, valueToWrite: "150x3@7", expectedCurrentValue: ""))
    try ctx.save()
    let client = LiveSheetClient(
        grid: replanGrid([
            "C15": "Squat", "D15": "1", "F15": "5",
            "D16": "1", "F16": "5",
            "D17": "1", "F17": "3",
            "C20": "Bench Press", "D20": "1"
        ]),
        rowsInsertedBeforeFetch: [2: [16]],
        editsLandingBeforeFetch: [2: ["K17": "205x3@9"]]
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

@MainActor
@Test func replanningAfterTheCoachInsertsARowRefusesTheCorrectionAndPlansTheNextSetAgainstTheFreshRead() async throws {
    let container = try makeReplanContainer()
    let ctx = container.mainContext
    ctx.insert(replanPendingWrite(createdAt: 1, setIndex: 1, valueToWrite: "185x5@8", expectedCurrentValue: ""))
    ctx.insert(replanPendingWrite(createdAt: 2, setIndex: 1, valueToWrite: "205x3@10", expectedCurrentValue: "205x3@9"))
    ctx.insert(replanPendingWrite(createdAt: 3, setIndex: 2, valueToWrite: "150x3@7", expectedCurrentValue: ""))
    try ctx.save()
    let client = LiveSheetClient(
        grid: replanGrid([
            "C15": "Squat", "D15": "1", "F15": "5",
            "D16": "1", "F16": "5",
            "D17": "1", "F17": "3",
            "C20": "Bench Press", "D20": "1"
        ]),
        rowsInsertedBeforeFetch: [2: [16]]
    )
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.cell("K16") == "")
    #expect(client.cell("K17") == "185x5@8")
    #expect(client.cell("K18") == "150x3@7")
    #expect(client.fetchCount == 2)
    #expect(sync.outcome == .writesRefused(["Squat: Expected '205x3@9', found '185x5@8'"]))
    let remaining = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(remaining.map(\.status) == [.conflict])
    #expect(remaining.map(\.valueToWrite) == ["205x3@10"])

    let entries = try ctx.fetch(FetchDescriptor<WriteTargetAuditEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    #expect(entries.map(\.selectedA1Target) == ["'Block 27'!K16", "'Block 27'!K17", "'Block 27'!K18"])
    #expect(entries.map(\.finalStatus) == [.succeeded, .conflict, .succeeded])
    let lineRow = ": Prescription Line row stores this Line's Set logs as a comma-separated list (Set 1 of the Line)."
    #expect(
        entries.map(\.rowScanDetails) == ["Selected row 16" + lineRow, "Selected row 17" + lineRow, "Selected row 18" + lineRow]
    )
    #expect(entries.first { $0.finalStatus == .conflict }?.valueCheckOutcome == "Expected '205x3@9', found '185x5@8'.")
}
