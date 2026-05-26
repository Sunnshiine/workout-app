import SwiftData
import Testing

@testable import WorkoutTracker

@Test func parsesFormattedWeightedSetLog() throws {
    let log = try #require(SetLog(formatted: "185x7@6.5"))
    #expect(log.weight == .pounds(185))
    #expect(log.reps == 7)
    #expect(log.rpe == 6.5)
    #expect(log.formatted == "185x7@6.5")
}

@Test func parsesFormattedBodyweightSetLog() throws {
    let log = try #require(SetLog(formatted: "BWx12@7"))
    #expect(log.weight == .bodyweight)
    #expect(log.reps == 12)
    #expect(log.rpe == 7)
    #expect(log.formatted == "BWx12@7")
}

@Test func rejectsMalformedSetLogStrings() {
    #expect(SetLog(formatted: "") == nil)
    #expect(SetLog(formatted: "185@7") == nil)
    #expect(SetLog(formatted: "185xseven@7") == nil)
    #expect(SetLog(formatted: "185x7@hard") == nil)
    #expect(SetLog(formatted: "nanx7@8") == nil)
    #expect(SetLog(formatted: "infx7@8") == nil)
    #expect(SetLog(formatted: "185x7@nan") == nil)
    #expect(SetLog(formatted: "185x7@inf") == nil)
}

@MainActor
@Test func exerciseSetStoresSetLogAsCodableData() throws {
    let set = ExerciseSet(index: 0, prescribedReps: "7", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    set.setLog = SetLog(weight: .pounds(185), reps: 7, rpe: 8)
    set.state = .logged

    #expect(set.setLogData != nil)
    #expect(set.setLog?.formatted == "185x7@8")
    #expect(set.state == .logged)

    set.setLog = nil
    #expect(set.setLogData == nil)
    #expect(set.setLog == nil)
}

@MainActor
@Test func exerciseSetSetLogRoundTripsThroughSwiftData() throws {
    let container = try ModelContainer(
        for: Block.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext
    let set = ExerciseSet(index: 0, prescribedReps: "7", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    set.setLog = SetLog(weight: .pounds(185), reps: 7, rpe: 8)
    set.state = .logged
    let ex = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil)
    ex.sets = [set]
    let session = Session(dayNumber: 1, date: nil)
    session.exercises = [ex]
    let week = Week(number: 1)
    week.sessions = [session]
    let block = Block(tabName: "Block 27", squatTM: nil, benchTM: nil, deadliftTM: nil)
    block.weeks = [week]

    ctx.insert(block)
    try ctx.save()

    let fetchedSet = try #require(try ctx.fetch(FetchDescriptor<Block>())
        .first?.weeks.first?.sessions.first?.exercises.first?.sets.first)
    #expect(fetchedSet.state == .logged)
    #expect(fetchedSet.setLog?.formatted == "185x7@8")
}

@MainActor
@Test func exerciseSetKeepsExistingSetLogDataWhenEncodingFails() throws {
    let set = ExerciseSet(index: 0, prescribedReps: "7", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    set.setLog = SetLog(weight: .pounds(185), reps: 7, rpe: 8)
    let originalData = try #require(set.setLogData)

    set.setLog = SetLog(weight: .pounds(.nan), reps: 7, rpe: 8)

    #expect(set.setLogData == originalData)
    #expect(set.setLog?.formatted == "185x7@8")
}
