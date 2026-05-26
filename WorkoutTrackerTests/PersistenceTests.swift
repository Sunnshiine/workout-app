import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func blockRoundTripsThroughSwiftData() throws {
    let container = try ModelContainer(
        for: Block.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext

    let set = ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE8", percentOneRM: nil, state: .pending)
    let ex = Exercise(name: "0:3:0 Standing Calve Raises", baseName: "Standing Calve Raises", cadence: "0:3:0", coachNote: nil)
    ex.sets = [set]
    let session = Session(dayNumber: 1, date: nil)
    session.exercises = [ex]
    let week = Week(number: 1)
    week.sessions = [session]
    let block = Block(tabName: "Block 27", squatTM: nil, benchTM: nil, deadliftTM: nil)
    block.weeks = [week]
    ctx.insert(block)
    try ctx.save()

    let fetched = try ctx.fetch(FetchDescriptor<Block>())
    #expect(fetched.count == 1)
    #expect(fetched[0].weeks.first?.sessions.first?.exercises.first?.sets.first?.prescribedReps == "12")
}
