import Foundation
import Testing
import WorkoutTracker

private func json(_ value: some Encodable) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Test func addressesRoundTripThroughTheirStringForm() throws {
    for raw in ["w1d1", "w12d6"] {
        #expect(try #require(SessionAddress(raw)).description == raw)
    }
    for raw in ["w1d1.e0", "w4d3.e12"] {
        #expect(try #require(ExerciseAddress(raw)).description == raw)
    }
    for raw in ["w1d1.e0.s0", "w4d3.e12.s7"] {
        #expect(try #require(SetAddress(raw)).description == raw)
    }
    #expect(SetAddress("w1d1.e0.s2") == SetAddress(exercise: ExerciseAddress(session: SessionAddress(week: 1, day: 1), order: 0), index: 2))
}

@Test func addressParsingIsStrict() {
    for raw in ["W1D1", "w1d1 ", " w1d1", "w1d", "w1d1.e0", "wd1", "w1d1.", "1d1"] {
        #expect(SessionAddress(raw) == nil, "\(raw)")
    }
    for raw in ["w1d1", "w1d1.e", "w1d1.e0.s0", "w1d1.E0", "w1d1e0"] {
        #expect(ExerciseAddress(raw) == nil, "\(raw)")
    }
    for raw in ["w1d1.e0", "w1d1.e0.s", "w1d1.e0.s0.x", "w1d1.e0.S0", "w1d1.s0"] {
        #expect(SetAddress(raw) == nil, "\(raw)")
    }
}

@Test func addressesEncodeAsTheirStringForm() throws {
    let encoded = try JSONEncoder().encode([SetAddress("w1d1.e0.s2")])
    #expect(String(bytes: encoded, encoding: .utf8) == "[\"w1d1.e0.s2\"]")
    let decoded = try JSONDecoder().decode([SetAddress].self, from: encoded)
    #expect(decoded == [SetAddress("w1d1.e0.s2")])
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(SetAddress.self, from: Data("\"nope\"".utf8))
    }
}

@MainActor
@Test func everyPublicOutputTypeEncodesToJSON() async throws {
    let app = try WorkoutApplication(
        environment: .inMemory(
            workbook: WorkbookScenario.freshBlock.workbook(),
            now: { Date(timeIntervalSince1970: 1_780_000_000) }
        )
    )

    let selected = try json(try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log"))
    #expect(selected["currentSession"] as? String == "w1d1")
    #expect((selected["syncOutcome"] as? [String: Any])?["status"] as? String == "clear")
    #expect((selected["sessions"] as? [[String: Any]])?.count == 5)

    let block = try #require(selected["block"] as? [String: Any])
    #expect(block["tabName"] as? String == "Block 27")
    #expect(block["squatTM"] as? Double == 365)
    #expect(block["benchTM"] as? Double == 245)
    #expect(block["deadliftTM"] as? Double == 455)

    let session = try json(try app.session(nil))
    let exercises = try #require(session["exercises"] as? [[String: Any]])
    let sets = try #require(exercises[0]["sets"] as? [[String: Any]])
    #expect(sets.map { $0["id"] as? String } == ["w1d1.e0.s0", "w1d1.e0.s1", "w1d1.e0.s2"])

    let log = try json(try app.log(try #require(SetAddress("w1d1.e0.s0")), setLog: "185x5@8"))
    #expect((log["set"] as? [String: Any])?["loggedAt"] as? String == "2026-05-28T20:26:40Z")
    #expect(log["pendingWriteCount"] as? Int == 1)

    let flush = try json(try await app.flush())
    #expect(flush["written"] as? Int == 1)

    let sheet = try json(try await app.sheet(tab: nil))
    #expect((sheet["cells"] as? [String: String])?["K15"] == "185x5@8")

    let sync = try json(try await app.sync())
    #expect(sync["currentSession"] as? String == "w1d1")
}

@MainActor
@Test func errorsExposeCodeMessageAndCandidates() async throws {
    let app = try WorkoutApplication(environment: .inMemory(workbook: WorkbookScenario.freshBlock.workbook()))
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: nil)

    do {
        _ = try app.log(try #require(SetAddress("w1d1.e0.s9")), setLog: "185x5@8")
        Issue.record("expected unknown_set")
    } catch let error as ApplicationError {
        #expect(error.code == "unknown_set")
        #expect(error.message == "w1d1.e0 has 3 Sets; no Set at w1d1.e0.s9.")
        #expect(error.candidates == ["w1d1.e0.s0", "w1d1.e0.s1", "w1d1.e0.s2"])
    }
    #expect(ApplicationError.notConfigured.candidates == nil)
    #expect(ApplicationError.notConfigured.message.contains("workout init"))
}

@Test func everyApplicationErrorVerbReportsACodeAMessageCandidatesAndAKind() {
    let cases: [(error: ApplicationError, code: String, message: String, candidates: [String]?, kind: ApplicationError.Kind)] = [
        (
            .notConfigured, "not_configured",
            "No spreadsheet is selected. Run `workout init --scenario fresh-block`.", nil, .environment
        ),
        (
            .noBlock, "no_block",
            "No Block is cached for the selected spreadsheet. Run `workout sync`.", nil, .domain
        ),
        (
            .invalidAddress("W1D1"), "invalid_address",
            "\"W1D1\" is not an address. Use w<week>d<day>, w<week>d<day>.e<order>, or "
                + "w<week>d<day>.e<order>.s<index>; `workout session` prints them.", nil, .domain
        ),
        (
            .invalidSetLog("185 for 5"), "invalid_set_log",
            "\"185 for 5\" is not a Set Log. Use {weight}x{reps}@{RPE}, for example 185x5@8 or BWx12@7. "
                + "RPE is one of 5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10.", nil, .domain
        ),
        (
            .notFound(.session, name: "w9d1", candidates: ["w1d1"]), "unknown_session",
            "No Session w9d1. This Block has 1 Sessions; `workout status` lists them.", ["w1d1"], .domain
        ),
        (
            .notFound(.exercise, name: "w1d1.e5", candidates: ["w1d1.e0"]), "unknown_exercise",
            "w1d1 has 1 Exercises; no Exercise at w1d1.e5.", ["w1d1.e0"], .domain
        ),
        (
            .notFound(.set, name: "w1d1.e0.s9", candidates: ["w1d1.e0.s0"]), "unknown_set",
            "w1d1.e0 has 1 Sets; no Set at w1d1.e0.s9.", ["w1d1.e0.s0"], .domain
        ),
        (
            .notFound(.tab, name: "Block 26", candidates: ["Block 27"]), "unknown_tab",
            "No tab named \"Block 26\". Tabs: Block 27.", ["Block 27"], .domain
        ),
        (
            .sessionUnavailable("w2d3"), "session_unavailable",
            "w2d3 is an Unavailable Session: the coach has not uploaded it yet. "
                + "`workout status` shows which are available.", nil, .domain
        ),
        (
            .sheetSwitchFailed("the sheet is offline"), "sheet_switch_failed",
            "Couldn't select the spreadsheet: the sheet is offline", nil, .environment
        ),
        (
            .sheetSwitchRequiresDiscard, "sheet_switch_requires_discard",
            "Pending writes exist for the current spreadsheet. Run `workout flush` before selecting another sheet.",
            nil, .domain
        ),
        (
            .syncFailed(.clear), "sync_failed",
            "Sync did not complete (clear). Check the workbook and run `workout sync` again.",
            nil, .environment
        ),
        (
            .syncFailed(.localWriteFailed), "sync_failed",
            "Sync did not complete (localWriteFailed). Check the workbook and run `workout sync` again.",
            nil, .conflict
        ),
        (
            .syncFailed(.sheetUnreachable), "sync_failed",
            "Sync did not complete (sheetUnreachable). Check the workbook and run `workout sync` again.",
            nil, .environment
        ),
        (
            .syncFailed(.writesQueued), "sync_failed",
            "Sync did not complete (writesQueued). Check the workbook and run `workout sync` again.",
            nil, .environment
        ),
        (
            .syncFailed(.writesRefused), "sync_failed",
            "Sync did not complete (writesRefused). Check the workbook and run `workout sync` again.",
            nil, .conflict
        ),
        (
            .syncFailed(.noBlockTab), "sync_failed",
            "Sync did not complete (noBlockTab). Check the workbook and run `workout sync` again.",
            nil, .conflict
        ),
        (
            .syncFailed(.parseWarnings), "sync_failed",
            "Sync did not complete (parseWarnings). Check the workbook and run `workout sync` again.",
            nil, .conflict
        ),
        (
            .syncFailed(.historyFillFailed), "sync_failed",
            "Sync did not complete (historyFillFailed). Check the workbook and run `workout sync` again.",
            nil, .conflict
        )
    ]

    for (error, code, message, candidates, kind) in cases {
        #expect(error.code == code)
        #expect(error.message == message, "\(code)")
        #expect(error.localizedDescription == message, "\(code)")
        #expect(error.candidates == candidates, "\(code)")
        #expect(error.kind == kind, "\(code)")
    }
}

@Test func aMissedLookupNamesWhatItSearchedAndHowManyItHeld() {
    #expect(
        ApplicationError.notFound(.session, name: "w9d1", candidates: ["w1d1", "w1d2"]).message
            == "No Session w9d1. This Block has 2 Sessions; `workout status` lists them."
    )
    #expect(
        ApplicationError.notFound(.exercise, name: "w1d1.e5", candidates: ["w1d1.e0", "w1d1.e1"]).message
            == "w1d1 has 2 Exercises; no Exercise at w1d1.e5."
    )
    #expect(
        ApplicationError.notFound(.set, name: "w1d1.e0.s9", candidates: ["w1d1.e0.s0"]).message
            == "w1d1.e0 has 1 Sets; no Set at w1d1.e0.s9."
    )
    #expect(
        ApplicationError.notFound(.tab, name: "Block 26", candidates: ["Block 27", "Block 28"]).message
            == "No tab named \"Block 26\". Tabs: Block 27, Block 28."
    )
}
