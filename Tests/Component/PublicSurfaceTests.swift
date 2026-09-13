import Foundation
import Testing
import WorkoutTracker

// Compiled without @testable on purpose: this file sees exactly what the CLI sees.

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
