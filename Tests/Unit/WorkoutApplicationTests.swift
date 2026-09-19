import Foundation
import Testing

@testable import WorkoutTracker

private let frozenNow = Date(timeIntervalSince1970: 1_780_000_000)

@MainActor
private func makeSelectedApp() async throws -> WorkoutApplication {
    let app = try WorkoutApplication(
        environment: .inMemory(workbook: WorkbookScenario.freshBlock.workbook(), now: { frozenNow })
    )
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
    return app
}

private func address(_ raw: String) throws -> SetAddress {
    try #require(SetAddress(raw))
}

@MainActor
@Test func selectingTheFixtureSpreadsheetSyncsTheBlockAndResolvesTheCurrentSession() async throws {
    let app = try await makeSelectedApp()

    let snapshot = try app.snapshot()

    #expect(snapshot.spreadsheetId == "FIXTURE")
    #expect(snapshot.spreadsheetTitle == "Fixture Training Log")
    #expect(snapshot.syncState == .idle)
    #expect(snapshot.pendingWriteCount == 0)
    let block = try #require(snapshot.block)
    #expect(block.tabName == "Block 27")
    #expect((block.squatTM, block.benchTM, block.deadliftTM) == (365, 245, 455))
    #expect(block.weekCount == 2)
    #expect(snapshot.currentSession == SessionAddress(week: 1, day: 1))
    #expect(snapshot.displayedSession == SessionAddress(week: 1, day: 1))
    #expect(snapshot.currentSessionReason == "No manual override is active, so Sheet-derived progress wins.")
    #expect(snapshot.currentSessionIsOverridden == false)
    #expect(snapshot.canMoveOn == true)
    #expect(snapshot.openExercises == [])
    #expect(snapshot.sessions.map(\.id.description) == ["w1d1", "w1d2", "w2d1", "w2d2", "w2d3"])
    #expect(snapshot.sessions.map(\.available) == [true, true, true, true, false])
    #expect(snapshot.sessions.map(\.isCurrent) == [true, false, false, false, false])
    #expect(snapshot.sessions[0].totalSetCount == 5)
}

@MainActor
@Test func theArcLogsThroughTheStoreFlushesToTheSheetAndReadsBackThroughTheParser() async throws {
    let app = try await makeSelectedApp()

    let report = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    #expect(report.set.state == "logged")
    #expect(report.set.setLog == "185x5@8")
    #expect(report.set.loggedAt == frozenNow)
    #expect(report.pendingWriteCount == 1)
    #expect(report.exerciseIsComplete == false)
    #expect(try app.snapshot().syncState == .idle)

    let flush = try await app.flush()
    #expect(flush == FlushReport(attempted: 1, written: 1, conflictedWrites: [], remainingPendingWrites: 0, syncState: .idle))

    let sheet = try await app.sheet(tab: nil)
    #expect(sheet.tab == "Block 27")
    #expect(sheet.cells["K15"] == "185x5@8")
    #expect(sheet.cells["I15"] == nil)

    let synced = try await app.sync()
    #expect(synced.syncState == .idle)
    #expect(synced.currentSession == SessionAddress(week: 1, day: 1))
    #expect(synced.pendingWriteCount == 0)

    let session = try app.session(SessionAddress(week: 1, day: 1))
    let squat = session.exercises[0]
    #expect(squat.name == "Back Squat")
    #expect(squat.sets.map(\.state) == ["logged", "pending", "pending"])
    #expect(squat.sets[0].setLog == "185x5@8")
    #expect(squat.sets[0].loggedAt == frozenNow)
    #expect(session.completedSetCount == 1)
}

@MainActor
@Test func loggingTheFinalSetEnqueuesTheNotesAndLastSetRPEWrites() async throws {
    let app = try await makeSelectedApp()

    let report = try app.log(address("w1d1.e0.s2"), setLog: "195x5@9")
    #expect(report.pendingWriteCount == 2)

    let writes = try app.sync.fetchPendingWriteRecords()
    #expect(writes.map(\.column) == [.notes, .lastSetRPE])
    #expect(writes.map(\.valueToWrite) == ["195x5@9", "9"])

    _ = try await app.flush()
    let sheet = try await app.sheet(tab: nil)
    #expect(sheet.cells["K15"] == ", , 195x5@9")
    #expect(sheet.cells["I15"] == "9")
}

@MainActor
@Test func skippingASetEnqueuesTheSetLogWriteAndSettlesTheSet() async throws {
    let app = try await makeSelectedApp()

    let report = try app.skip(address("w1d1.e0.s0"))
    #expect(report.set.state == "skipped")
    #expect(report.set.setLog == nil)
    #expect(report.pendingWriteCount == 1)

    let writes = try app.sync.fetchPendingWriteRecords()
    #expect(writes.map(\.column) == [.notes])
    #expect(writes.map(\.valueToWrite) == ["skip"])

    _ = try await app.flush()
    #expect(try await app.sheet(tab: nil).cells["K15"] == "skip")
}

@MainActor
@Test func aCoachNoteRedirectsTheSetLogToTheVisibleWritableRow() async throws {
    let app = try await makeSelectedApp()

    _ = try app.log(address("w1d1.e1.s0"), setLog: "135x8@8")
    _ = try await app.flush()

    let sheet = try await app.sheet(tab: nil)
    #expect(sheet.cells["K19"] == "Start w/ 10 sec hold")
    #expect(sheet.cells["K20"] == "135x8@8")
    _ = try await app.sync()
    #expect(try app.session(SessionAddress(week: 1, day: 1)).exercises[1].sets[0].state == "logged")
}

@MainActor
@Test func loggingTheSameSetTwiceEnqueuesTwice() async throws {
    let app = try await makeSelectedApp()

    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    let second = try app.log(address("w1d1.e0.s0"), setLog: "190x5@8")

    #expect(second.pendingWriteCount == 2)
    #expect(try app.sync.fetchPendingWriteRecords().map(\.expectedCurrentValue) == ["", "185x5@8"])
}

@MainActor
@Test func sessionNilIsTheCurrentSessionAndFollowsLogging() async throws {
    let app = try await makeSelectedApp()
    #expect(try app.session(nil).id == SessionAddress(week: 1, day: 1))

    _ = try app.log(address("w1d2.e0.s0"), setLog: "155x5@7")

    #expect(try app.session(nil).id == SessionAddress(week: 1, day: 2))
    #expect(try app.snapshot().openExercises.map(\.description) == ["w1d1.e0", "w1d1.e1"])
}

@MainActor
@Test func addressErrorsCarryTheCandidates() async throws {
    let app = try await makeSelectedApp()

    #expect(throws: ApplicationError.notFound(.set, name: "w1d1.e0.s9", candidates: ["w1d1.e0.s0", "w1d1.e0.s1", "w1d1.e0.s2"])) {
        try app.log(address("w1d1.e0.s9"), setLog: "185x5@8")
    }
    #expect(throws: ApplicationError.notFound(.exercise, name: "w1d1.e5", candidates: ["w1d1.e0", "w1d1.e1"])) {
        try app.log(address("w1d1.e5.s0"), setLog: "185x5@8")
    }
    #expect(
        throws: ApplicationError.notFound(.session, name: "w9d1", candidates: ["w1d1", "w1d2", "w2d1", "w2d2", "w2d3"])
    ) {
        try app.session(SessionAddress(week: 9, day: 1))
    }
    #expect(throws: ApplicationError.sessionUnavailable("w2d3")) {
        try app.log(address("w2d3.e0.s0"), setLog: "185x5@8")
    }
    #expect(throws: ApplicationError.invalidSetLog("185 for 5")) {
        try app.log(address("w1d1.e0.s0"), setLog: "185 for 5")
    }
    #expect(throws: ApplicationError.invalidSetLog("185x5@5.5")) {
        try app.log(address("w1d1.e0.s0"), setLog: "185x5@5.5")
    }
    #expect(try app.snapshot().pendingWriteCount == 0)
}

@MainActor
@Test func unconfiguredApplicationRefusesSheetVerbsButStillSnapshots() async throws {
    let app = try WorkoutApplication(environment: .inMemory(workbook: WorkbookScenario.freshBlock.workbook()))

    #expect(try app.snapshot().spreadsheetId == nil)
    #expect(try app.snapshot().block == nil)
    #expect(try app.snapshot().currentSessionReason == "No Block is loaded, so no Current Session is resolved.")
    await #expect(throws: ApplicationError.notConfigured) { try await app.flush() }
    await #expect(throws: ApplicationError.notConfigured) { try await app.sync() }
    #expect(throws: ApplicationError.noBlock) { try app.session(nil) }
}

@MainActor
@Test func aConflictedWriteIsReportedByEveryLaterFlushAndSync() async throws {
    let app = try await makeSelectedApp()
    let client = try #require(app.sheetsClient as? LocalWorkbookSheetsClient)
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    try await client.updateCells(spreadsheetId: "FIXTURE", range: "'Block 27'!K15", values: [["200x5@8"]])

    let first = try await app.flush()
    #expect(first.attempted == 1)
    #expect(first.written == 0)
    #expect(first.conflictedWrites.count == 1)
    #expect(first.conflictedWrites[0].hasPrefix("Back Squat:"))
    #expect(first.remainingPendingWrites == 1)

    let second = try await app.flush()
    #expect(
        second
            == FlushReport(attempted: 0, written: 0, conflictedWrites: first.conflictedWrites, remainingPendingWrites: 1, syncState: .idle)
    )

    let synced = try await app.sync()
    #expect(synced.conflictedWrites == first.conflictedWrites)
    #expect(synced.pendingWriteCount == 1)
}

@MainActor
@Test func sheetReadsAnyNamedTabAndRejectsUnknownOnes() async throws {
    let app = try await makeSelectedApp()

    #expect(try await app.sheet(tab: "Block 27").cells["C12"] == "Day 1")
    await #expect(throws: ApplicationError.notFound(.tab, name: "Block 26", candidates: ["Block 27"])) {
        try await app.sheet(tab: "Block 26")
    }
}
