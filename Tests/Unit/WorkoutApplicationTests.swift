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
    #expect(snapshot.syncOutcome.status == .clear)
    #expect(snapshot.pendingWriteCount == 0)
    let block = try #require(snapshot.block)
    #expect(block.tabName == "Block 27")
    #expect((block.squatTM, block.benchTM, block.deadliftTM) == (365, 245, 455))
    #expect(block.weekCount == 2)
    #expect(snapshot.currentSession == SessionAddress(week: 1, day: 1))
    #expect(snapshot.viewedSession == SessionAddress(week: 1, day: 1))
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
    #expect(try app.snapshot().syncOutcome.status == .clear)

    let flush = try await app.flush()
    #expect(
        flush
            == FlushReport(
                attempted: 1,
                written: 1,
                conflictedWrites: [],
                remainingPendingWrites: 0,
                syncOutcome: SyncOutcomeSnapshot(.clear)
            )
    )

    let sheet = try await app.sheet(tab: nil)
    #expect(sheet.tab == "Block 27")
    #expect(sheet.cells["K15"] == "185x5@8")
    #expect(sheet.cells["I15"] == nil)

    let synced = try await app.sync()
    #expect(synced.syncOutcome.status == .clear)
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
@Test func skippingTheFinalSetClearsItsLastSetRPEInTheWorkbook() async throws {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s2"), setLog: "195x5@9")
    _ = try await app.flush()
    #expect(try await app.sheet(tab: nil).cells["I15"] == "9")

    _ = try app.skip(address("w1d1.e0.s2"))
    _ = try await app.flush()

    let sheet = try await app.sheet(tab: nil)
    #expect(sheet.cells["K15"] == ", , skip")
    #expect(sheet.cells["I15"] == nil)
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
@Test(.timeLimit(.minutes(1))) func syncIsRefusedWhileAnotherSyncIsRunning() async throws {
    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let app = try WorkoutApplication(
        environment: AppEnvironment(storage: .inMemory, sheetsClient: client, defaults: .inMemory(), now: { frozenNow }, seed: nil)
    )
    app.settings.setSpreadsheet(id: "held-sheet")

    let first = Task { try await app.sync() }
    await client.waitUntilHeld()
    await #expect(throws: ApplicationError.syncFailed(.clear)) { try await app.sync() }
    client.release()

    #expect(try await first.value.block?.tabName == "Block 27")
    #expect(client.tabTitleReads == 1)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func selectingASheetWhileASyncRunsIsRefusedWithTheReason() async throws {
    let client = HeldSheetsClient(titles: ["Intro", "Block 27"], grid: WorkoutFixtureScenarios.replacementSheetGrid)
    let app = try WorkoutApplication(
        environment: AppEnvironment(storage: .inMemory, sheetsClient: client, defaults: .inMemory(), now: { frozenNow }, seed: nil)
    )
    app.settings.setSpreadsheet(id: "held-sheet")

    let first = Task { try await app.sync() }
    await client.waitUntilHeld()
    await #expect(throws: ApplicationError.sheetSwitchFailed("A sync is already in progress.")) {
        try await app.selectSpreadsheet(id: "other-sheet", title: nil)
    }
    client.release()

    _ = try await first.value
    #expect(try app.snapshot().spreadsheetId == "held-sheet")
}

@MainActor
@Test func selectingAnotherSheetOverQueuedSetLogsAsksForTheirDiscard() async throws {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")

    await #expect(throws: ApplicationError.sheetSwitchRequiresDiscard) {
        try await app.selectSpreadsheet(id: "OTHER", title: nil)
    }

    let snapshot = try app.snapshot()
    #expect(snapshot.spreadsheetId == "FIXTURE")
    #expect(snapshot.pendingWriteCount == 1)
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
            == FlushReport(
                attempted: 0,
                written: 0,
                conflictedWrites: first.conflictedWrites,
                remainingPendingWrites: 1,
                syncOutcome: SyncOutcomeSnapshot(.clear)
            )
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

private func wire(_ suggestion: LoadSuggestionSnapshot) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try #require(String(bytes: try encoder.encode(suggestion), encoding: .utf8))
}

@MainActor
@Test func anRPETargetEstimatesFromTheLastOtherSessionThenRecalibratesFromSetOneToday() async throws {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "315x5@7")
    _ = try app.log(address("w1d1.e0.s1"), setLog: "295x5@6")

    let setOne = try app.session(SessionAddress(week: 2, day: 1)).exercises[0].sets[0]
    #expect(
        try wire(setOne.loadSuggestion)
            == #"{"basis":{"origin":"history","session":"Block 27 · W1 D1","setLog":"315x5@7","text":"from 315x5@7 · W1 D1"},"#
            + #""kind":"estimate","weight":315}"#
    )

    let report = try app.log(address("w2d1.e0.s0"), setLog: "315x5@8.5")
    #expect(try wire(report.set.loadSuggestion) == #"{"kind":"none"}"#)

    let setTwo = try app.session(SessionAddress(week: 2, day: 1)).exercises[0].sets[1]
    #expect(
        try wire(setTwo.loadSuggestion)
            == #"{"basis":{"origin":"today","set":"w2d1.e0.s0","setLog":"315x5@8.5","text":"from Set 1 today"},"#
            + #""kind":"estimate","weight":300}"#
    )
}

@MainActor
@Test func anRPETargetNeverEstimatesFromItsOwnSession() async throws {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "315x5@7")
    _ = try app.log(address("w2d1.e0.s1"), setLog: "400x5@7")

    let setOne = try app.session(SessionAddress(week: 2, day: 1)).exercises[0].sets[0]

    #expect(setOne.loadSuggestion.weight == 315)
    #expect(setOne.loadSuggestion.basis?.session == "Block 27 · W1 D1")
}

@MainActor
@Test func skippingTheOnlyLoggedSetLeavesNoBasisAfterFlushAndSync() async throws {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "315x5@7")
    _ = try app.skip(address("w1d1.e0.s0"))
    _ = try await app.flush()
    _ = try await app.sync()

    let setOne = try app.session(SessionAddress(week: 2, day: 1)).exercises[0].sets[0]

    #expect(try wire(setOne.loadSuggestion) == #"{"kind":"none"}"#)
}

@MainActor
@Test func deletingTheOnlySetLogLeavesNoBasis() async throws {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "315x5@7")
    let set = try #require(
        app.workout.block?.weeks.first { $0.number == 1 }?
            .sessions.first { $0.dayNumber == 1 }?
            .exercises.first { $0.order == 0 }?
            .sets.first { $0.index == 0 }
    )

    try app.workout.deleteLog(for: set)

    let setOne = try app.session(SessionAddress(week: 2, day: 1)).exercises[0].sets[0]
    #expect(try wire(setOne.loadSuggestion) == #"{"kind":"none"}"#)
}

@MainActor
@Test func sayingAWholeSetLogsItThroughTheSameWriteAsLog() async throws {
    let app = try await makeSelectedApp()

    let report = try app.say("185 for 5 at 8", at: address("w1d1.e0.s0"))

    #expect(report.heard == "185 for 5 at 8")
    #expect(report.outcome == .logged)
    #expect(report.setLog == "185x5@8")
    #expect(report.set.state == "logged")
    #expect(report.set.setLog == "185x5@8")
    #expect(report.pendingWriteCount == 1)
    _ = try await app.flush()
    #expect(try await app.sheet(tab: nil).cells["K15"] == "185x5@8")
}

@MainActor
@Test func sayingOnlyTheRPEOfAFreshBlocksFirstSetIsMissingTheWeightAndQueuesNothing() async throws {
    let app = try await makeSelectedApp()

    let report = try app.say("RPE 9", at: address("w1d1.e0.s0"))

    #expect(report.outcome == .missingValues)
    #expect(report.missing == ["weight"])
    #expect(report.setLog == nil)
    #expect(report.set.state == "pending")
    #expect(report.pendingWriteCount == 0)
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

@MainActor
@Test func sayingTheRPEAfterSetOneLogsTheWeightTheCardEstimates() async throws {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    let estimate = try #require(try app.session(nil).exercises[0].sets[1].loadSuggestion.weight)

    let report = try app.say("at 9", at: address("w1d1.e0.s1"))

    #expect(report.outcome == .logged)
    #expect(report.setLog == SetLog(weight: .pounds(estimate), reps: 5, rpe: .nine).formatted)
}

@MainActor
@Test func sayingSameAgainRepeatsTheNearestEarlierSetLogOfTheExercise() async throws {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")

    let report = try app.say("same again", at: address("w1d1.e0.s1"))

    #expect(report.outcome == .logged)
    #expect(report.setLog == "185x5@8")
    #expect(report.pendingWriteCount == 2)
}

/// A typed Set Log takes any weight, so a spoken one does too, wherever the words show it hides no value.
@MainActor
@Test(
    "Saying a weight of 1,000 or more writes it to the Sheet as said",
    arguments: [
        ("1000 for 5 at 8", "1000x5@8"), ("1005 for 5 at 8", "1005x5@8"), ("1500 for 5 at 8", "1500x5@8"),
        ("1000 pounds for 1 at 10", "1000x1@10"), ("1,000 for 5 at 8", "1000x5@8"), ("1,005 pounds for 5 at 8", "1005x5@8"),
        ("one thousand for 5 at 8", "1000x5@8"), ("a thousand for 2 at 9", "1000x2@9")
    ]
)
func sayingAWeightOfAThousandOrMoreWritesItAsSaid(transcript: String, setLog: String) async throws {
    let app = try await makeSelectedApp()

    let report = try app.say(transcript, at: address("w1d1.e0.s0"))

    #expect(report.outcome == .logged)
    #expect(report.setLog == setLog)
    _ = try await app.flush()
    #expect(try await app.sheet(tab: nil).cells["K15"] == setLog)
}

@MainActor
@Test func sayingSkipSkipsTheSetAndWritesSkip() async throws {
    let app = try await makeSelectedApp()

    let report = try app.say("skip it", at: address("w1d1.e0.s0"))

    #expect(report.outcome == .skipped)
    #expect(report.set.state == "skipped")
    #expect(try app.sync.fetchPendingWriteRecords().map(\.valueToWrite) == ["skip"])
    _ = try await app.flush()
    #expect(try await app.sheet(tab: nil).cells["K15"] == "skip")
}

@MainActor
@Test func aRejectedSpokenSetReportsWhyAndQueuesNothing() async throws {
    let app = try await makeSelectedApp()

    let offLadder = try app.say("185 for 5 RPE 4", at: address("w1d1.e0.s0"))
    let nothingToRepeat = try app.say("same again", at: address("w1d1.e0.s0"))
    let conflicting = try app.say("135 for 4, 8 reps", at: address("w1d1.e0.s0"))
    let fused = try app.say("40542 at nine.", at: address("w1d1.e0.s0"))
    let ambiguous = try app.say("135 for 49", at: address("w1d1.e0.s0"))
    let implausible = try app.say("12.47 for 3", at: address("w1d1.e0.s0"))

    #expect(offLadder.outcome == .rejected)
    #expect(offLadder.rejection == SpokenSetRejectionSnapshot(reason: .offLadderRPE, field: nil, value: 4))
    #expect(nothingToRepeat.rejection?.reason == .nothingToRepeat)
    #expect(conflicting.rejection == SpokenSetRejectionSnapshot(reason: .conflicting, field: "reps", value: nil))
    #expect(fused.rejection == SpokenSetRejectionSnapshot(reason: .fusedNumber, field: nil, value: nil))
    #expect(ambiguous.rejection == SpokenSetRejectionSnapshot(reason: .ambiguous, field: nil, value: nil))
    #expect(implausible.rejection == SpokenSetRejectionSnapshot(reason: .implausible, field: "weight", value: nil))
    #expect(conflicting.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

/// The second Set once the first is logged, so its card pre-fills a weight, reps, and an RPE, and any
/// value the grammar wrongly hears completes a Set Log that would be queued for the Sheet.
@MainActor
private func appWhoseSecondSetCardHoldsEveryValue() async throws -> WorkoutApplication {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    return app
}

@MainActor
@Test func oneValueSaidOnACardThatHoldsEveryValueQueuesItsWrite() async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say("for 5", at: address("w1d1.e0.s1"))

    #expect(report.outcome == .logged)
    #expect(try app.sync.fetchPendingWriteRecords().count == 2)
}

/// "185 for 5 and 5" once logged RPE 5 over the card's RPE, so a number after "and" or a misheard
/// "to" leaves the RPE to the athlete.
@MainActor
@Test(
    "A weight for reps and a number on a card that holds every value is missing the RPE and queues nothing",
    arguments: ["185 for 5 and 5", "Body weight for 12 to 7"]
)
func aWeightForRepsAndANumberOnACardThatHoldsEveryValueIsMissingTheRPEAndQueuesNothing(transcript: String) async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say(transcript, at: address("w1d1.e0.s1"))

    #expect(report.outcome == .missingValues)
    #expect(report.missing == ["rpe"])
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().count == 1)
}

/// Each of these once wrote a Set Log nobody said, or is a transcriber's misreading of one.
@MainActor
@Test(
    "A transcript the grammar rejects queues no write, even on a card that holds every value",
    arguments: [
        "5 at 8", "for 5, 8", "5 reps, 8", "eight reps nine", "four at eight", "1 85", "1,85", "one 85", "1 8 5",
        "185, 45, at 8", "405 42", "eight", "8", "ten", "nine point five", "185, 5, 8", "185 and 5", "for 5 and 8",
        "8 reps of 135", "nine five for five", "at nine five for five", "five or six reps at eight",
        "twenty five or thirty reps at eight", "1854.5 for 5",
        "135 for 16", "Two.", "245 for three 8 1/2", "185+58", "315 for 19.5", "185 for 5 at 80%",
        "185 for 5 and 8 reps", "185 for 5 at 8 reps", "185 for 5, 185 for 5", "same weight", "8½", "95 pounds to 67"
    ]
)
func aRejectedTranscriptQueuesNoWrite(transcript: String) async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say(transcript, at: address("w1d1.e0.s1"))

    #expect(report.outcome == .rejected)
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().count == 1)
}

/// Each of these once wrote a Set Log the lifter did not say: a value no Set Log holds, "or" between two
/// numbers, a command naming which Set, a value said twice, a dropped minus sign.
@MainActor
@Test(
    "A transcript no Set Log holds or that says a value twice queues no write on a card that holds every value",
    arguments: [
        "135 for 0", "135 for 8.5", "0 for 5", "30 or 25 reps", "25 or 20 reps", "50 or 40 reps", "twenty five or twenty reps",
        "thirty or twenty five reps at 8",
        "60 or 50 reps", "40 or 30", "25 per 30", "20 per 25", "forty four five", "ninety four five", "skip set one",
        "skip one set", "same as set one", "same as last time", "repeat set one", "one again", "same one", "135 for -5",
        "135 for 5 at -8", "185 for 5 and 3 at 8", "185 for 5 and 5 at 8", "185 for 5 and 8 at 9", "185 for 5 and 5 RPE 8",
        "185 for 5 for 5 for 5", "185 for 5 reps, 5 reps, 5 reps", "135 for 3 and 135 at 9", "135 for 5 at 8 at",
        "135 for 5 at 8 for", "135 for 5 at 8 x", "135 for 5 at 8 of", "135 for 5 at 8 add", "135 for 5 for"
    ]
)
func aTranscriptNoSetLogHoldsQueuesNoWrite(transcript: String) async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say(transcript, at: address("w1d1.e0.s1"))

    #expect(report.outcome == .rejected)
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().count == 1)
}

/// Speaking logs what typing on the card logs, however light the weight, fine its fraction, or many its reps.
@MainActor
@Test(
    "A Spoken Set of any weight and rep count a lifter logs queues its write",
    arguments: [
        ("5 by 5", "5x5@7"), ("4 for 5", "4x5@7"), ("10 for 12 at 9", "10x12@9"), ("135 for 45", "135x45@7"),
        ("187.25 for 5", "187.25x5@7"), ("8 reps at 12", "12x8@7"), ("5 reps with 12", "12x5@7"), ("19 per 5", "19x5@7")
    ]
)
func aSpokenSetOfAnyValueALifterLogsQueuesItsWrite(transcript: String, setLog: String) async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say(transcript, at: address("w1d1.e0.s1"))

    #expect(report.outcome == .logged)
    #expect(report.setLog == setLog)
    #expect(try app.sync.fetchPendingWriteRecords().count == 2)
}

/// Each of these once logged the card's or the cut-off RPE as if the lifter had finished saying it.
@MainActor
@Test(
    "A transcript cut off after its RPE is missing the RPE and queues no write on a card that holds every value",
    arguments: [
        "135 for 5 at eight and a", "135 for 5 at 8 and", "135 for 5 at 8 and a", "135 for 5 at 8 and uh",
        "135 for 5 rpe 8 and", "135 for 5 reps at 8 and a", "rpe 8 and a", "rpe 8 and", "at 8 and", "135 for 5 at nine and",
        "135 for 5 at nine and a", "135 for 5 at 9 and a", "135 for 5 at 6 and a", "135 for 5 at 7 and a",
        "135 for 3 at 9 and", "8 reps at 9 and", "8 reps rpe 9 and", "135 for 5 at 8 and then", "135 for 5 at 8 and then uh",
        "135 for 5 at 8 so and"
    ]
)
func aTranscriptCutOffAfterItsRPEQueuesNoWrite(transcript: String) async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say(transcript, at: address("w1d1.e0.s1"))

    #expect(report.outcome == .missingValues)
    #expect(report.missing == ["rpe"])
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().count == 1)
}

@MainActor
@Test func sayingToAnUnknownSetThrowsTheSameLookupErrorAsLog() async throws {
    let app = try await makeSelectedApp()

    #expect(throws: ApplicationError.notFound(.set, name: "w1d1.e0.s9", candidates: ["w1d1.e0.s0", "w1d1.e0.s1", "w1d1.e0.s2"])) {
        try app.say("185 for 5 at 8", at: address("w1d1.e0.s9"))
    }
}

@MainActor
@Test func dictatingWritesOnlyWhatTheMostLikelyTranscriptReads() async throws {
    let app = try await makeSelectedApp()

    let report = try app.dictate(["RPE 9", "185 for 5 at 8"], at: address("w1d1.e0.s0"))

    #expect(report.heard == "RPE 9")
    #expect(report.outcome == .missingValues)
    #expect(report.missing == ["weight"])
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

@MainActor
@Test func dictatingASetOnlyTheLessLikelyTranscriptsReadIsAmbiguousAndWritesNothing() async throws {
    let app = try await makeSelectedApp()

    let report = try app.dictate(["um", "185 for 5 at 8", "185 for 5 at 8"], at: address("w1d1.e0.s0"))

    #expect(report.heard == "um")
    #expect(report.outcome == .rejected)
    #expect(report.rejection == SpokenSetRejectionSnapshot(reason: .ambiguous, field: nil, value: nil))
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

@MainActor
@Test func dictatingWithNoTranscriptHeardNothing() async throws {
    let app = try await makeSelectedApp()

    let report = try app.dictate([], at: address("w1d1.e0.s0"))

    #expect(report.heard == "")
    #expect(report.outcome == .rejected)
    #expect(report.rejection?.reason == .nothingHeard)
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

@available(iOS 26, macOS 26, *)
@MainActor
@Test func hearingRefusesAnUnknownSetAndAFileThatIsNotAudioBeforeItListens() async throws {
    let app = try await makeSelectedApp()
    let notAudio = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).aiff")
    try Data("185 for 5 at 8".utf8).write(to: notAudio)
    defer { try? FileManager.default.removeItem(at: notAudio) }

    await #expect(throws: ApplicationError.notFound(.set, name: "w1d1.e0.s9", candidates: ["w1d1.e0.s0", "w1d1.e0.s1", "w1d1.e0.s2"])) {
        try await app.hear(notAudio, at: address("w1d1.e0.s9")) { _ in }
    }
    await #expect(throws: ApplicationError.unreadableRecording(notAudio.path)) {
        try await app.hear(notAudio, at: address("w1d1.e0.s0")) { _ in }
    }
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

@MainActor
@Test func aHeardSetReportsEveryTranscriptBesideWhatTheMostLikelyOneDid() async throws {
    let app = try await makeSelectedApp()
    let candidates = ["135 for 5 at 8.", "135 four 5 at 8."]
    let report = HearReport(candidates: candidates, report: try app.dictate(candidates, at: address("w1d1.e0.s0")))

    let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])

    #expect(json["candidates"] as? [String] == candidates)
    #expect(json["heard"] as? String == "135 for 5 at 8.")
    #expect(json["outcome"] as? String == "logged")
    #expect(json["setLog"] as? String == "135x5@8")
}

@MainActor
@Test func dictatingAWholeSetFromTheMostLikelyTranscriptLogsIt() async throws {
    let app = try await makeSelectedApp()

    let report = try app.dictate(["185 for 5 at 8", "185 for 5 at 9"], at: address("w1d1.e0.s0"))

    #expect(report.outcome == .logged)
    #expect(report.setLog == "185x5@8")
    #expect(report.set.state == "logged")
    #expect(report.pendingWriteCount == 1)
}
