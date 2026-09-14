import Testing

@testable import WorkoutTracker

@Test(arguments: WorkbookScenario.allCases)
func everyScenarioParsesCleanlyWithAnAvailableSession(scenario: WorkbookScenario) throws {
    let workbook = scenario.workbook()
    let tab = try #require(workbook.tabs.keys.first { blockNumber(from: $0) != nil })
    let snapshot = try #require(workbook.tabs[tab]?.snapshot)

    let parsed = SheetParser().parse(snapshot: snapshot, tabName: tab)

    #expect(parsed.warnings == [])
    #expect(parsed.block.weeks.contains { $0.days.contains { !$0.exercises.isEmpty } })
}

@Test func freshBlockScenarioHasTheDocumentedShape() throws {
    let workbook = WorkbookScenario.freshBlock.workbook()
    let snapshot = try #require(workbook.tabs["Block 27"]?.snapshot)

    let parsed = SheetParser().parse(snapshot: snapshot, tabName: "Block 27")
    let block = parsed.block

    #expect(workbook.spreadsheetId == "FIXTURE")
    #expect(workbook.title == "Fixture Training Log")
    #expect(block.squatTM == 365)
    #expect(block.benchTM == 245)
    #expect(block.deadliftTM == 455)
    #expect(block.weeks.map(\.number) == [1, 2])
    #expect(block.weeks[0].days.map(\.dayNumber) == [1, 2])
    #expect(block.weeks[1].days.map(\.dayNumber) == [1, 2, 3])

    let week1Day1 = block.weeks[0].days[0]
    #expect(week1Day1.exercises.map(\.name) == ["Back Squat", "2-3:1:0 BB RDL"])
    #expect(week1Day1.exercises[0].sets.map(\.prescribedReps) == ["5", "5", "5"])
    #expect(week1Day1.exercises[0].sets.map(\.prescribedLoad) == ["RPE7", "RPE7", "RPE7"])
    #expect(week1Day1.exercises[1].cadence == "2-3:1:0")
    #expect(week1Day1.exercises[1].baseName == "BB RDL")
    #expect(week1Day1.exercises[1].coachNote == "Start w/ 10 sec hold")
    #expect(week1Day1.exercises[1].sets.count == 2)
    #expect(block.weeks[0].days[1].exercises.map(\.name) == ["Bench Press", "BW Pull Up"])
    #expect(block.weeks[0].days[1].exercises[1].sets.map(\.prescribedLoad) == ["BW", "BW"])
    #expect(block.weeks[1].days[2].exercises.isEmpty)
    #expect(block.weeks.flatMap(\.days).flatMap(\.exercises).flatMap(\.sets).allSatisfy { $0.state == .pending })
}
