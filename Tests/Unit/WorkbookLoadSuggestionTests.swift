import Foundation
import Testing

@testable import WorkoutTracker

// The `%1RM` and Drop arms of `LoadSuggestionEngine`, reached from cells a coach could have typed
// rather than from a Set built in Swift (#596). `LoadSuggestionEngineTests` pins each arm's
// arithmetic; these pin the wiring that feeds it, workbook cell through `SheetParser`, sync and
// the store to the suggestion the Set card pre-fills, on both of the parser's paths: one
// Prescription Line per Exercise (Kevin's template) and one per Set (J. Alarcon's, ADR-0010).

@MainActor
private func selectedApp(_ scenario: WorkbookScenario) async throws -> WorkoutApplication {
    let app = try WorkoutApplication(
        environment: .inMemory(
            workbook: scenario.workbook(),
            now: { Date(timeIntervalSince1970: 1_780_000_000) }
        )
    )
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
    return app
}

@MainActor
private func sets(_ app: WorkoutApplication, _ session: SessionAddress, exercise order: Int) throws -> [SetSnapshot] {
    let exercise = try #require(try app.session(session).exercises.first { $0.order == order })
    return exercise.sets
}

@MainActor
@Test func aPercentOneRMOnEachPrescriptionLineSuggestsThatShareOfTheTrainingMax() async throws {
    let app = try await selectedApp(.partialUpload)

    // Back Squat, Training Max 315: one Line per Set.
    let squat = try sets(app, SessionAddress(week: 1, day: 1), exercise: 0)
    #expect(squat.map(\.percentOneRM) == ["75%", "80%", "85%"])
    #expect(squat.map(\.loadSuggestion.kind) == [.weight, .weight, .weight])
    #expect(squat.map(\.loadSuggestion.weight) == [237.5, 252.5, 267.5])

    // Deadlift, Training Max 405.
    let deadlift = try sets(app, SessionAddress(week: 2, day: 1), exercise: 0)
    #expect(deadlift.map(\.percentOneRM) == ["75%", "80%"])
    #expect(deadlift.map(\.loadSuggestion.weight) == [305, 325])
}

@MainActor
@Test func aPercentOneRMOnASingleLineSuggestsThatShareForEverySetOfTheLine() async throws {
    let app = try await selectedApp(.freshBlock)

    // Bench Press, Training Max 245: one Line of three Sets, so one `%1RM` cell prescribes all three.
    let bench = try sets(app, SessionAddress(week: 1, day: 2), exercise: 0)
    #expect(bench.map(\.percentOneRM) == ["70%", "70%", "70%"])
    #expect(bench.map(\.loadSuggestion.kind) == [.weight, .weight, .weight])
    #expect(bench.map(\.loadSuggestion.weight) == [172.5, 172.5, 172.5])
}

@MainActor
@Test func aDropLoadSuggestsItsShareOffTheSetLoggedBeforeIt() async throws {
    let app = try await selectedApp(.partialUpload)
    let rdl = SessionAddress(week: 1, day: 1)

    let before = try sets(app, rdl, exercise: 1)
    #expect(before.map(\.prescribedLoad) == ["Drop 17.5%", "Drop 17.5%"])
    // Nothing logged yet in the Exercise, so there is no weight to drop from.
    #expect(before.map(\.loadSuggestion.kind) == [.none, .none])

    _ = try app.log(try #require(SetAddress("w1d1.e1.s0")), setLog: "225x8@8")

    let after = try sets(app, rdl, exercise: 1)
    #expect(after[1].loadSuggestion.kind == .weight)
    // 225 less 17.5%, to the nearest 2.5 lb.
    #expect(after[1].loadSuggestion.weight == 185)
}
