import Foundation
import Testing

@testable import WorkoutTracker

private let fixtureSheet = "FIXTURE"
private let tab = "Block 27"

private func address(_ raw: String) throws -> SetAddress {
    try #require(SetAddress(raw))
}

private func pain(_ words: String? = nil) throws -> SetFlag {
    try #require(SetFlag(kind: .pain, text: words))
}

private func hideRow(_ number: Int, in workbook: inout LocalWorkbook) {
    workbook.tabs[tab]?.hiddenRows[number] = SheetRowVisibility(hiddenByUser: true, hiddenByFilter: false)
}

@MainActor
private func makeApp(over client: any SheetsClient) async throws -> WorkoutApplication {
    let app = try WorkoutApplication(environment: .inMemory(sheets: client))
    _ = try await app.selectSpreadsheet(id: fixtureSheet, title: "Fixture Training Log")
    return app
}

@MainActor
private func makeApp(
    editing edit: (inout LocalWorkbook) -> Void = { _ in },
    failingUpdateRequests failed: Set<Int> = []
) async throws -> (app: WorkoutApplication, sheet: LocalWorkbookSheetsClient) {
    var workbook = WorkbookScenario.freshBlock.workbook()
    edit(&workbook)
    let sheet = LocalWorkbookSheetsClient(workbook: workbook, failedUpdateRequestNumbers: failed)
    return (try await makeApp(over: sheet), sheet)
}

@MainActor
private func standing(of setAddress: String, in app: WorkoutApplication) throws -> [SetFlagStanding] {
    try app.setSnapshot(address(setAddress)).setFlags?.map(\.standing) ?? []
}

extension WorkoutApplication {
    fileprivate func setSnapshot(_ address: SetAddress) throws -> SetSnapshot {
        let session = try session(address.exercise.session)
        let exercise = try #require(session.exercises.first { $0.id == address.exercise })
        return try #require(exercise.sets.first { $0.id == address })
    }
}

@MainActor
@Test func aSetFlagLandsAsACellNoteAndChangesNoValueInTheTab() async throws {
    let (app, sheet) = try await makeApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    _ = try await app.flush()
    let before = try await app.sheet(tab: tab).cells

    let report = try app.flag(address("w1d1.e0.s0"), as: pain("left hip"))
    #expect(report.pendingWriteCount == 1)
    let flush = try await app.flush()

    let after = try await app.sheet(tab: tab)
    #expect((flush.written, flush.remainingPendingWrites) == (1, 0))
    #expect(after.cells == before)
    #expect(after.cellNotes == ["K15": "Set 1 · Pain: left hip"])
    #expect(await sheet.recordedBatches.count == 1, "only the Set Log took a value write")
}

@MainActor
@Test func aSetWithNoSetLogCellYetTakesTheExercisesWritableCell() async throws {
    let (app, _) = try await makeApp()

    _ = try app.flag(address("w1d1.e0.s0"), as: pain())
    _ = try app.flag(address("w1d1.e1.s1"), as: pain())
    _ = try await app.flush()

    let sheet = try await app.sheet(tab: tab)
    #expect(sheet.cellNotes == ["K15": "Set 1 · Pain", "K20": "Set 2 · Pain"], "K19 holds the RDL's Coach Note, so its Set Logs go on K20")
    #expect(sheet.cells["K15"] == nil)
    #expect(sheet.cells["K19"] == "Start w/ 10 sec hold")
}

@MainActor
@Test func aSetFlagAddsToTheCoachsCellNoteAndKeepsEveryWordOfIt() async throws {
    let coach = "Watch the hips\n\n  then brace"
    let (app, _) = try await makeApp(editing: { $0.tabs[tab]?.cellNotes["K15"] = coach })

    _ = try app.flag(address("w1d1.e0.s0"), as: pain("left hip"))
    _ = try await app.flush()

    #expect(try await app.sheet(tab: tab).cellNotes["K15"] == "\(coach)\nSet 1 · Pain: left hip")
}

@MainActor
@Test func flagsOnOneSharedCellLandInTheOrderTheyWereRaised() async throws {
    let (app, _) = try await makeApp()

    _ = try app.flag(address("w1d1.e0.s1"), as: pain("first"))
    _ = try app.flag(address("w1d1.e0.s0"), as: pain("second"))
    _ = try await app.flush()

    #expect(try await app.sheet(tab: tab).cellNotes["K15"] == "Set 2 · Pain: first\nSet 1 · Pain: second")
}

@MainActor
@Test func aFlushWhoseResponseWasLostLeavesOneLineWhenItRunsAgain() async throws {
    let line = "Set 1 · Pain: left hip"
    let (app, _) = try await makeApp(editing: { $0.tabs[tab]?.cellNotes["K15"] = line })

    _ = try app.flag(address("w1d1.e0.s0"), as: pain("left hip"))
    let flush = try await app.flush()

    #expect(flush.remainingPendingWrites == 0)
    #expect(try await app.sheet(tab: tab).cellNotes["K15"] == line)
}

@MainActor
@Test func aSetLogWrittenAfterAFlagKeepsTheCellNote() async throws {
    let (app, _) = try await makeApp()
    _ = try app.flag(address("w1d1.e0.s0"), as: pain())
    _ = try await app.flush()

    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    _ = try app.log(address("w1d1.e0.s1"), setLog: "185x5@8")
    _ = try await app.flush()

    let sheet = try await app.sheet(tab: tab)
    #expect(sheet.cells["K15"] == "185x5@8, 185x5@8")
    #expect(sheet.cellNotes["K15"] == "Set 1 · Pain")
}

@MainActor
@Test func aSetLogAndAFlagInOneFlushBothLandWithTheLogFirst() async throws {
    let (app, sheet) = try await makeApp()

    _ = try app.flag(address("w1d1.e0.s0"), as: pain())
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    let flush = try await app.flush()

    #expect(flush.written == 2)
    let tabNow = try await app.sheet(tab: tab)
    #expect((tabNow.cells["K15"], tabNow.cellNotes["K15"]) == ("185x5@8", "Set 1 · Pain"))
    #expect(await sheet.recordedCellNotes.count == 1)
}

@MainActor
@Test func aCoachsEditToTheValueNeverRefusesAFlag() async throws {
    let (app, sheet) = try await makeApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    _ = try await app.flush()
    try await sheet.write([SheetCellWrite(tabName: tab, row: 14, col: 10, value: "190x5@8")], spreadsheetId: fixtureSheet)

    _ = try app.flag(address("w1d1.e0.s0"), as: pain())
    let flush = try await app.flush()

    #expect(flush.conflictedWrites.isEmpty)
    let tabNow = try await app.sheet(tab: tab)
    #expect((tabNow.cells["K15"], tabNow.cellNotes["K15"]) == ("190x5@8", "Set 1 · Pain"))
}

@MainActor
@Test func aSetLogRefusedByTheSheetDoesNotTakeTheFlagWithIt() async throws {
    let (app, sheet) = try await makeApp()
    try await sheet.write([SheetCellWrite(tabName: tab, row: 14, col: 10, value: "190x5@8")], spreadsheetId: fixtureSheet)

    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    _ = try app.flag(address("w1d1.e0.s0"), as: pain())
    let flush = try await app.flush()

    #expect(flush.conflictedWrites.count == 1, "\(flush.conflictedWrites)")
    #expect(flush.syncOutcome.status == .writesRefused)
    #expect(try await app.sheet(tab: tab).cellNotes["K15"] == "Set 1 · Pain")
    #expect(try standing(of: "w1d1.e0.s0", in: app) == [.landed])
}

@MainActor
@Test func aFlagTheSheetKeepsTurningDownDoesNotHoldUpTheSetLogsBehindIt() async throws {
    let (app, sheet) = try await makeApp(failingUpdateRequests: [2])

    _ = try app.flag(address("w1d1.e0.s0"), as: pain())
    _ = try app.log(address("w1d1.e0.s1"), setLog: "185x5@8")
    let flush = try await app.flush()

    #expect(flush.remainingPendingWrites == 1)
    #expect(flush.syncOutcome.status == .writesQueued)
    #expect(try await app.sheet(tab: tab).cells["K15"] == ", 185x5@8", "the Set Log landed")
    #expect(try standing(of: "w1d1.e0.s0", in: app) == [.unsynced])
    #expect(await sheet.recordedCellNotes.isEmpty)

    let retry = try await app.flush()
    #expect(retry.remainingPendingWrites == 0)
    #expect(try await app.sheet(tab: tab).cellNotes["K15"] == "Set 1 · Pain")
    #expect(try standing(of: "w1d1.e0.s0", in: app) == [.landed])
}

@MainActor
@Test func aFlagWithNoVisibleWritableRowIsRefusedRatherThanSentAcrossTheCoachsNote() async throws {
    let (app, _) = try await makeApp(editing: { workbook in
        for row in 20...36 { hideRow(row, in: &workbook) }
    })

    _ = try app.flag(address("w1d1.e1.s0"), as: pain())
    _ = try app.flag(address("w1d1.e0.s0"), as: pain())
    let flush = try await app.flush()

    #expect(flush.conflictedWrites.count == 1)
    #expect(flush.syncOutcome.status == .setFlagsRefused)
    #expect(try await app.sheet(tab: tab).cellNotes == ["K15": "Set 1 · Pain"])
    #expect(try standing(of: "w1d1.e1.s0", in: app) == [.refused])
    #expect(try standing(of: "w1d1.e0.s0", in: app) == [.landed])
    #expect(try app.snapshot().pendingWriteCount == 1, "a refused flag waits for a discard, as a refused Set Log does")
}

@MainActor
@Test func aSetFlagWaitsOfflineThenLandsAndTheSetSaysSoAtEachStep() async throws {
    let drive = LocalDrive([WorkbookScenario.freshBlock.workbook()])
    let app = try await makeApp(over: drive)
    await drive.disconnect(fixtureSheet)

    let report = try app.flag(address("w1d1.e0.s0"), as: pain("left hip"))
    #expect(report.set.setFlags?.first?.standing == .unsynced)
    #expect(report.set.setFlags?.first?.line == "Set 1 · Pain: left hip")

    let offline = try await app.flush()
    #expect(offline.remainingPendingWrites == 1)
    #expect(offline.syncOutcome.status == .writesQueued)
    #expect(try standing(of: "w1d1.e0.s0", in: app) == [.unsynced])

    await drive.reconnect(fixtureSheet)
    let online = try await app.flush()
    #expect(online.remainingPendingWrites == 0)
    #expect(online.syncOutcome.status == .clear)
    #expect(try standing(of: "w1d1.e0.s0", in: app) == [.landed])
    #expect(try await app.sheet(tab: tab).cellNotes["K15"] == "Set 1 · Pain: left hip")
}

@MainActor
@Test func aQueuedFlagStaysUnsyncedThroughASyncThatCannotWriteIt() async throws {
    let (app, _) = try await makeApp(failingUpdateRequests: [1])

    _ = try app.flag(address("w1d1.e0.s0"), as: pain())
    let report = try await app.sync()

    #expect(report.pendingWriteCount == 1)
    #expect(try standing(of: "w1d1.e0.s0", in: app) == [.unsynced])
    #expect(try await app.sheet(tab: tab).cellNotes.isEmpty)
}

@MainActor
@Test func aLaterSyncReadsTheFlagBackFromTheSheetSoOnlyItsOwnSetShowsIt() async throws {
    let (app, _) = try await makeApp()
    _ = try app.flag(address("w1d1.e0.s1"), as: pain("left hip"))
    _ = try await app.flush()

    _ = try await app.sync()

    #expect(try standing(of: "w1d1.e0.s1", in: app) == [.landed])
    #expect(try app.setSnapshot(address("w1d1.e0.s1")).setFlags?.first?.text == "left hip")
    #expect(try standing(of: "w1d1.e0.s0", in: app).isEmpty, "Set 1 shares the cell, and the line names Set 2")
}

@MainActor
@Test func aLineTheCoachDeletesTakesTheMarkWithItOnTheNextSync() async throws {
    let drive = LocalDrive([WorkbookScenario.freshBlock.workbook()])
    let app = try await makeApp(over: drive)
    _ = try app.flag(address("w1d1.e0.s0"), as: pain())
    _ = try await app.flush()
    #expect(try standing(of: "w1d1.e0.s0", in: app) == [.landed])

    try await drive.writeCellNote(SheetCellNoteWrite(tabName: tab, row: 14, col: 10, text: "Thanks, noted"), spreadsheetId: fixtureSheet)
    _ = try await app.sync()

    #expect(try standing(of: "w1d1.e0.s0", in: app).isEmpty)
}

@MainActor
@Test func aClearLeavesTheFlagBecauseTheAthleteStillToldTheCoach() async throws {
    let (app, _) = try await makeApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    _ = try app.flag(address("w1d1.e0.s0"), as: pain())
    _ = try await app.flush()

    _ = try app.deleteLog(address("w1d1.e0.s0"))
    _ = try await app.flush()

    let tabNow = try await app.sheet(tab: tab)
    #expect(tabNow.cells["K15"] == nil)
    #expect(tabNow.cellNotes["K15"] == "Set 1 · Pain")
    #expect(try standing(of: "w1d1.e0.s0", in: app) == [.landed])
}

@MainActor
@Test func flaggingMovesNoSetState() async throws {
    let (app, _) = try await makeApp()
    _ = try app.skip(address("w1d1.e0.s0"))

    let report = try app.flag(address("w1d1.e0.s0"), as: pain("skipped it because of this"))

    #expect(report.set.state == "skipped")
    #expect(try app.flag(address("w1d1.e0.s1"), as: pain()).set.state == "pending")
}

@Test func theValuePlannerRefusesASetFlagSoItsLineCanNeverReachACell() throws {
    let planner = SheetWritePlanner()
    let snapshot = try planner.snapshot(for: #require(WorkbookScenario.freshBlock.workbook().snapshots[tab]))
    let request = SheetWriteRequest(
        session: SessionCoordinate(blockTab: tab, address: SessionAddress(week: 1, day: 1)),
        exerciseName: "Back Squat",
        setIndex: 0,
        column: .setFlag,
        operation: .upsert,
        valueToWrite: "Set 1 · Pain",
        expectedCurrentValue: ""
    )

    #expect(throws: SheetWriterError.self) { try planner.plan(request, in: snapshot) }
}

@Test func aFlagsAuditSaysNoValueWasChecked() throws {
    let planner = SheetWritePlanner()
    let snapshot = try planner.snapshot(for: #require(WorkbookScenario.freshBlock.workbook().snapshots[tab]))
    let request = SheetWriteRequest(
        session: SessionCoordinate(blockTab: tab, address: SessionAddress(week: 1, day: 1)),
        exerciseName: "Back Squat",
        setIndex: 0,
        column: .setFlag,
        operation: .upsert,
        valueToWrite: "Set 1 · Pain",
        expectedCurrentValue: ""
    )

    let target = try planner.target(for: request, in: snapshot)
    let details = planner.auditDetails(for: request, target: target, in: snapshot)

    #expect(details.selectedA1Target == "'Block 27'!K15")
    #expect(details.valueCheckOutcome == "Not checked because a Set Flag changes no value.")
    #expect(PendingWriteDiagnostic.columnLabel(for: .setFlag) == "Set Flag")
}

@Test func aRefusalOfOnlyFlagsSaysFlagAndOneBesideASetLogStaysTheLogs() {
    #expect(SyncOutcome(refusedWrites: [], refusedSetFlags: ["a"], queued: 0) == .setFlagsRefused(["a"]))
    #expect(SyncOutcome(refusedWrites: ["b"], refusedSetFlags: ["a"], queued: 0) == .writesRefused(["b", "a"]))
    #expect(SyncOutcome.sync(sheetRead: .clear, flush: .setFlagsRefused(["a"])) == .setFlagsRefused(["a"]))

    let banner = SyncStatusBannerPresentation(outcome: .setFlagsRefused(["Back Squat: gone"]), isSyncing: false)
    #expect(banner?.text == "The sheet changed, so your flag was not written")
    #expect(banner?.detail == "Back Squat: gone")
    #expect(SyncNowDetail.text(outcome: .setFlagsRefused(["a"]), isSyncing: false, hasSheet: true) == "Flag not written")
    #expect(SyncOutcomeSnapshot(.setFlagsRefused(["a"])).status == .setFlagsRefused)
}
