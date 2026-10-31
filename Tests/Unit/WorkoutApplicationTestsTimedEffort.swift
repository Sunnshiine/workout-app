import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func aSetPrintsTheTimedEffortItsExerciseOffers() async throws {
    let app = try await makeSelectedApp()
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    func wire(_ snapshot: TimedEffortSnapshot?) throws -> String? {
        try snapshot.map { String(bytes: try encoder.encode($0), encoding: .utf8) } ?? nil
    }

    let exercises = try app.session(SessionAddress(week: 1, day: 1)).exercises
    let timedSet = TimedEffortSnapshot(.timedSet(try #require(EffortDuration("40 sec"))))

    #expect(try exercises[0].sets.map { try wire($0.timedEffort) } == [nil, nil, nil])
    #expect(try exercises[1].sets.map { try wire($0.timedEffort) } == Array(repeating: #"{"kind":"openingHold","seconds":10}"#, count: 2))
    #expect(try wire(timedSet) == #"{"kind":"timedSet","seconds":40}"#)
}
