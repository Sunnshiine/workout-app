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
    #expect(String(decoding: encoded, as: UTF8.self) == "[\"w1d1.e0.s2\"]")
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
    #expect((selected["syncState"] as? [String: Any])?["status"] as? String == "idle")
    #expect((selected["sessions"] as? [[String: Any]])?.count == 5)

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

@Test func everyApplicationErrorCaseReportsACodeAMessageAndCandidates() {
    let cases: [(error: ApplicationError, code: String, echoes: String?, candidates: [String]?)] = [
        (.notConfigured, "not_configured", nil, nil),
        (.noBlock, "no_block", nil, nil),
        (.invalidAddress("W1D1"), "invalid_address", "W1D1", nil),
        (.invalidSetLog("185 for 5"), "invalid_set_log", "185 for 5", nil),
        (.notFound(.session, name: "w9d1", candidates: ["w1d1"]), "unknown_session", "w9d1", ["w1d1"]),
        (.notFound(.exercise, name: "w1d1.e5", candidates: ["w1d1.e0"]), "unknown_exercise", "w1d1.e5", ["w1d1.e0"]),
        (.notFound(.set, name: "w1d1.e0.s9", candidates: ["w1d1.e0.s0"]), "unknown_set", "w1d1.e0.s9", ["w1d1.e0.s0"]),
        (.notFound(.tab, name: "Block 26", candidates: ["Block 27"]), "unknown_tab", "Block 26", ["Block 27"]),
        (.sessionUnavailable("w2d3"), "session_unavailable", "w2d3", nil),
        (.sheetSwitchFailed("the sheet is offline"), "sheet_switch_failed", "the sheet is offline", nil),
        (.sheetSwitchRequiresDiscard, "sheet_switch_requires_discard", nil, nil),
        (.syncFailed(.conflict(["Back Squat: rejected"])), "sync_failed", nil, nil)
    ]

    for (error, code, echoes, candidates) in cases {
        #expect(error.code == code)
        #expect(error.localizedDescription == error.message, "\(code)")
        #expect(error.message.count > 20, "\(code)")
        #expect(error.candidates == candidates, "\(code)")
        if let echoes {
            #expect(error.message.contains(echoes), "\(code)")
        }
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
