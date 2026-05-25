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
                                        percentOneRM: nil
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
    #expect(block.weeks.first?.sessions.first?.exercises.first?.sets.first?.state == .pending)
}
