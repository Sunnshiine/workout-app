import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func buildsModelGraphFromParsedBlock() throws {
    let parsed = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            ParsedWeek(
                number: 1,
                days: [
                    ParsedSession(
                        dayNumber: 1,
                        date: nil,
                        exercises: [
                            ParsedExercise(
                                name: "0:3:0 Calf",
                                baseName: "Calf",
                                cadence: "0:3:0",
                                coachNote: nil,
                                sets: [
                                    ParsedSet(
                                        index: 0,
                                        prescribedReps: "12",
                                        prescribedLoad: "RPE8",
                                        percentOneRM: nil,
                                        setLog: SetLog(weight: .pounds(25), reps: 12, rpe: 7)
                                    ),
                                    ParsedSet(
                                        index: 1,
                                        prescribedReps: "10",
                                        prescribedLoad: "RPE9",
                                        percentOneRM: nil,
                                        setLog: nil
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        ]
    )
    let block = BlockBuilder.makeBlock(from: parsed)
    #expect(block.tabName == "Block 27")
    #expect(block.weeks.first?.sessions.first?.exercises.first?.cadence == "0:3:0")
    let set = try #require(block.weeks.first?.sessions.first?.exercises.first?.sets.first)
    #expect(set.state == .logged)
    let data = try #require(set.setLogData)
    #expect(try JSONDecoder().decode(SetLog.self, from: data) == SetLog(weight: .pounds(25), reps: 12, rpe: 7))
    let pendingSet = try #require(block.weeks.first?.sessions.first?.exercises.first?.sets.last)
    #expect(pendingSet.state == .pending)
    #expect(pendingSet.setLogData == nil)
}
