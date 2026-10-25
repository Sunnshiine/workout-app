import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func selectedApp() async throws -> WorkoutApplication {
    let app = try WorkoutApplication(environment: .inMemory(workbook: WorkbookScenario.freshBlock.workbook()))
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
    return app
}

/// Fixture press `line` as press `number`, for the Set at `address` in `block`, named `exercise`.
private func press(
    _ line: Int,
    number: Int,
    at address: String,
    exercise: String,
    in block: String = "Block 27"
) throws -> DictationRecord {
    let moved = DictationRecordFixtures.lines[line]
        .replacing(/"id":"[^"]+"/, with: #""id":"6F1C2D0E-0000-4000-8000-\#(String(format: "%012d", number))""#)
        .replacing(/"address":"[^"]+"/, with: #""address":"\#(address)""#)
        .replacing(/"exercise":"[^"]+"/, with: #""exercise":"\#(exercise)""#)
        .replacing(/"block":"[^"]+"/, with: #""block":"\#(block)""#)
    return try DictationRecordFixtures.record(moved)
}

private func label(_ number: Int, _ state: SetState, _ setLog: String?) throws -> DictationRecord.Label {
    let json =
        #"{"record":"6F1C2D0E-0000-4000-8000-\#(String(format: "%012d", number))","state":"\#(state.rawValue)""#
        + (setLog.map { #","setLog":"\#($0)"}"# } ?? "}")
    return try JSONDecoder().decode(DictationRecord.Label.self, from: Data(json.utf8))
}

private func address(_ raw: String) throws -> SetAddress {
    try #require(SetAddress(raw))
}

@MainActor
@Test func aWriteIsLabelledWithWhatItsSetHoldsNowWhetherItStoodOrTheAthleteChangedIt() async throws {
    let app = try await selectedApp()
    let stood = try press(0, number: 1, at: "w1d1.e0.s0", exercise: "Back Squat")
    let corrected = try press(4, number: 2, at: "w1d1.e0.s1", exercise: "Back Squat")
    let skipped = try press(0, number: 3, at: "w1d1.e0.s2", exercise: "Back Squat")
    let cleared = try press(4, number: 4, at: "w1d1.e1.s0", exercise: "2-3:1:0 BB RDL")
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    _ = try app.log(address("w1d1.e0.s1"), setLog: "135x5@8")
    _ = try app.skip(address("w1d1.e0.s2"))

    let labels = app.labels(for: [stood, corrected, skipped, cleared])

    #expect(
        labels.labels == [
            try label(1, .logged, "185x5@8"),
            try label(2, .logged, "135x5@8"),
            try label(3, .skipped, nil),
            try label(4, .pending, nil)
        ]
    )
}

@MainActor
@Test func aPressThatWroteNothingOrWhoseSetIsGoneHasNoLabel() async throws {
    let app = try await selectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    let rejected = try press(3, number: 1, at: "w1d1.e0.s0", exercise: "Back Squat")
    let cancelled = try DictationRecordFixtures.record(DictationRecordFixtures.lines[2])
    let otherBlock = try press(0, number: 2, at: "w1d1.e0.s0", exercise: "Back Squat", in: "Block 26")
    let renamed = try press(0, number: 3, at: "w1d1.e0.s0", exercise: "Front Squat")
    let noSuchSet = try press(0, number: 4, at: "w1d1.e0.s7", exercise: "Back Squat")
    let held = try press(0, number: 5, at: "w1d1.e0.s0", exercise: "Back Squat")

    let labels = app.labels(for: [rejected, cancelled, otherBlock, renamed, noSuchSet, held])

    #expect(labels.labels.map(\.record) == [held.id])
}

@Test(
    arguments: [
        (SetState.logged, "185x5@8", DictationScoring.Truth.write(.setLog("185x5@8"))),
        (.logged, "felt heavy", .write(.setLog("felt heavy"))),
        (.skipped, nil, .write(.skip)),
        (.pending, nil, nil)
    ] as [(SetState, String?, DictationScoring.Truth?)]
)
func aLabelIsWhatTheAthleteMeantUnlessTheyClearedTheSet(state: SetState, setLog: String?, truth: DictationScoring.Truth?) throws {
    #expect(try label(1, state, setLog).truth == truth)
}

@Test func labelsReadBackAsTheyWereWrittenAndRefuseASetLogTheirStateCannotHold() throws {
    let json =
        #"{"labels":[{"record":"6F1C2D0E-0000-4000-8000-000000000001","setLog":"185x5@8","state":"logged"},"#
        + #"{"record":"6F1C2D0E-0000-4000-8000-000000000002","state":"pending"}],"schema":1}"#

    let labels = try JSONDecoder().decode(DictationLabels.self, from: Data(json.utf8))

    #expect(labels.labels == [try label(1, .logged, "185x5@8"), try label(2, .pending, nil)])
    #expect(String(bytes: try DictationRecord.lineEncoder().encode(labels), encoding: .utf8) == json)
    #expect(throws: DecodingError.self) { try label(3, .logged, nil) }
    #expect(throws: DecodingError.self) { try label(3, .skipped, "185x5@8") }
    let otherSchema = Data(json.replacingOccurrences(of: #""schema":1"#, with: #""schema":2"#).utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(DictationLabels.self, from: otherSchema) }
}
