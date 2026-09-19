import Testing

@testable import WorkoutTracker

/// One Exercise shaped the way issue #498 describes: a stale Legacy Log in the header Notes cell,
/// one Unstructured Set Log the athlete wrote on the Visible Writable Row below it, and two more
/// prescribed Sets never logged.
private func snapshotWithLegacyLogAndUnstructuredSetLog() -> SheetSnapshot {
    SheetSnapshot(
        values: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
                "C15": "Standing Calve Raises", "D15": "3", "F15": "12", "H15": "RPE 9",
                "K15": "25x12, 12",
                "K16": "felt heavy"
            ],
            rows: 22,
            cols: 30
        )
    )
}

private func parsedBlock() -> ParsedBlockModel {
    SheetParser().parse(snapshot: snapshotWithLegacyLogAndUnstructuredSetLog(), tabName: "Block 27").block
}

private func parsedExercise() throws -> ParsedExercise {
    try #require(parsedBlock().weeks.first?.days.first?.exercises.first)
}

@Test func parsingLeavesUnloggedSetsPendingWhenAnUnstructuredSetLogSupersedesTheLegacyLog() throws {
    let exercise = try parsedExercise()

    #expect(exercise.legacyLog == "25x12, 12")
    #expect(exercise.sets[0].unstructuredSetLog == "felt heavy")
    #expect(exercise.sets.map(\.state) == [.logged, .pending, .pending])
}

@Test func lastPerformedReadsTheUnstructuredSetLogRatherThanTheLegacyLog() throws {
    let entry = try #require(LastPerformedExtractor.entries(from: parsedBlock()).first)

    #expect(entry.resultText == "felt heavy")
}

@MainActor
@Test func theExerciseStaysIncompleteWhenTheLegacyLogNoLongerCompletesItsUnloggedSets() throws {
    let block = BlockBuilder.makeBlock(from: parsedBlock())
    let exercise = try #require(block.weeks.first?.sessions.first?.exercises.first)

    #expect(exercise.isComplete == false)
    #expect(exercise.pendingSetCount == 2)
}
