import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func makeApp() async throws -> WorkoutApplication {
    let app = try WorkoutApplication(
        environment: .inMemory(
            workbook: WorkbookScenario.hiddenExerciseBelowCoachNote.workbook(),
            now: { Date(timeIntervalSince1970: 1_780_000_000) }
        )
    )
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: nil)
    return app
}

private func set(_ text: String) throws -> SetAddress {
    try #require(SetAddress(text))
}

@MainActor
private func setLogs(in app: WorkoutApplication) throws -> [String?] {
    let session = try app.session(SessionAddress(week: 1, day: 1))
    let rdl = try #require(session.exercises.first { $0.name == "2-3:1:0 BB RDL" })
    return rdl.sets.map(\.setLog)
}

@MainActor
@Test func theAthleteLogsEachSetPastAHiddenExerciseAcrossSyncs() async throws {
    let app = try await makeApp()

    _ = try app.log(try set("w1d1.e1.s0"), setLog: "105x9@9")
    _ = try await app.sync()
    #expect(try await app.sheet(tab: nil).cells["K22"] == "105x9@9")
    #expect(try setLogs(in: app) == ["105x9@9", nil])

    _ = try app.log(try set("w1d1.e1.s1"), setLog: "105x8@8")
    let report = try await app.sync()
    #expect(report.conflictedWrites == [])
    #expect(try await app.sheet(tab: nil).cells["K22"] == "105x9@9, 105x8@8")
    #expect(try await app.sheet(tab: nil).cells["I19"] == "8")
    #expect(try setLogs(in: app) == ["105x9@9", "105x8@8"])
    #expect(try app.snapshot().pendingWriteCount == 0)
}

@MainActor
@Test func theAthleteEditsAndClearsASetLogPastAHiddenExercise() async throws {
    let app = try await makeApp()
    _ = try app.log(try set("w1d1.e1.s0"), setLog: "105x9@9")
    _ = try app.log(try set("w1d1.e1.s1"), setLog: "105x8@8")
    _ = try await app.sync()

    _ = try app.log(try set("w1d1.e1.s0"), setLog: "110x9@9")
    _ = try await app.sync()
    #expect(try await app.sheet(tab: nil).cells["K22"] == "110x9@9, 105x8@8")

    _ = try app.deleteLog(try set("w1d1.e1.s1"))
    let report = try await app.sync()
    #expect(report.conflictedWrites == [])
    #expect(try setLogs(in: app) == ["110x9@9", nil])
}

@MainActor
@Test func loggingPastAHiddenExerciseLeavesItsRowsAndItsAbsenceAlone() async throws {
    let app = try await makeApp()
    _ = try app.log(try set("w1d1.e1.s0"), setLog: "105x9@9")
    _ = try await app.sync()

    #expect(try await app.sheet(tab: nil).cells["K21"] == "100x10@8")
    let session = try app.session(SessionAddress(week: 1, day: 1))
    #expect(session.exercises.map(\.name) == ["Back Squat", "2-3:1:0 BB RDL", "0:2:0 Preacher Curl"])
}
