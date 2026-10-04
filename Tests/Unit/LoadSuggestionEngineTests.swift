import Foundation
import Testing

@testable import WorkoutTracker

private func logged(_ weight: Weight) -> SetLog {
    SetLog(weight: weight, reps: 5, rpe: .eight)
}

@Test func suggestsLoadForDropPrescriptionFromPreviousSetWeight() {
    #expect(suggest(load: "Drop 17.5%", today: [(index: 0, setLog: logged(.pounds(225)))]) == .prescribedWeight(185))
}

@Test func suggestsLoadForPercentOneRMPrescriptionFromTrainingMax() {
    #expect(suggest(load: "RPE6", percentOneRM: "75%", trainingMax: 265) == .prescribedWeight(200))
}

@Test func roundsLoadSuggestionToNearestPlateIncrement() {
    #expect(suggest(load: "Drop 12%", today: [(index: 0, setLog: logged(.pounds(185)))]) == .prescribedWeight(162.5))
}

@Test func bodyweightPrescriptionPreFillsBodyweight() {
    #expect(suggest(load: "BW") == .bodyweight)
}

@Test func bodyweightWinsOverAPresentPercentOneRM() {
    #expect(suggest(load: "BW", percentOneRM: "75%", trainingMax: 265) == .bodyweight)
}

@Test("Unsupported Prescribed Load returns no Load Suggestion", arguments: ["RPE 5", "Start conservative"])
func unsupportedPrescribedLoadReturnsNone(prescribedLoad: String) {
    #expect(
        suggest(load: prescribedLoad, trainingMax: 265, today: [(index: 0, setLog: logged(.pounds(225)))]) == .noSuggestion
    )
}

@Test func missingContextReturnsNoneForLoadSuggestion() {
    #expect(suggest(load: "Drop 17.5%", trainingMax: 265) == .noSuggestion)
    #expect(suggest(load: "RPE6", percentOneRM: "75%") == .noSuggestion)
}

@Test func dropReadsTheNearestEarlierSet() {
    #expect(
        suggest(load: "Drop 20%", today: [(index: 1, setLog: logged(.pounds(225))), (index: 0, setLog: logged(.pounds(185)))])
            == .prescribedWeight(180)
    )
}

@Test func dropPassesOverABodyweightSetToTheNextOneBack() {
    #expect(
        suggest(load: "Drop 20%", today: [(index: 1, setLog: logged(.bodyweight)), (index: 0, setLog: logged(.pounds(185)))])
            == .prescribedWeight(147.5)
    )
}

@Test func dropOnTheFirstSetHasNothingToDropFrom() {
    #expect(suggest(load: "Drop 20%") == .noSuggestion)
}

private let block27W1D2 = SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 2))

private func entry(_ resultText: String) -> LastPerformedOccurrence {
    LastPerformedOccurrence(
        fullName: "Back Squat",
        baseName: "Back Squat",
        resultText: resultText,
        performedOn: Date(timeIntervalSinceReferenceDate: 0),
        source: block27W1D2.storageValue
    )
}

private func suggest(
    reps: String = "5",
    load: String = "RPE8",
    percentOneRM: String? = nil,
    trainingMax: Double? = nil,
    today earlierSets: [(index: Int, setLog: SetLog)] = [],
    history: String? = nil
) -> LoadSuggestion {
    LoadSuggestionEngine.suggest(
        LoadSuggestionInputs(
            prescribedReps: reps,
            prescribedLoad: load,
            percentOneRM: percentOneRM,
            trainingMax: trainingMax,
            earlierSets: earlierSets,
            lastPerformed: history.map(entry)
        )
    )
}

private func setLog(_ formatted: String) throws -> SetLog {
    try #require(SetLog(formatted: formatted))
}

private func basis(_ formatted: String, _ origin: LoadBasis.Origin) throws -> LoadBasis {
    try #require(LoadBasis(setLog: setLog(formatted), origin: origin))
}

@Test func aHistorySetLogEstimatesAHarderTargetThroughTheRPETable() throws {
    #expect(suggest(history: "315x5@7") == .estimate(325, basis: try basis("315x5@7", .history(block27W1D2))))
}

@Test func anEarlierSetTodayIsTheBasisBeforeAnyHistory() throws {
    #expect(
        suggest(today: [(index: 0, setLog: try setLog("315x5@7"))], history: "405x5@7")
            == .estimate(325, basis: try basis("315x5@7", .today(setIndex: 0)))
    )
}

@Test func anUnusableNearerSetTodayIsPassedOverForAnEarlierUsableOne() throws {
    let today = [(index: 1, setLog: try setLog("BWx5@8")), (index: 0, setLog: try setLog("315x5@7"))]

    #expect(suggest(today: today) == .estimate(325, basis: try basis("315x5@7", .today(setIndex: 0))))
}

@Test func aSetThatRanHarderTodayLowersTheNextSet() throws {
    #expect(
        suggest(load: "RPE7", today: [(index: 0, setLog: try setLog("315x5@8.5"))], history: "315x5@7")
            == .estimate(300, basis: try basis("315x5@8.5", .today(setIndex: 0)))
    )
}

@Test func theHistoryBasisIsTheEntrysHighestRPESetLog() throws {
    #expect(
        suggest(load: "RPE7", history: "315x5@7, 295x5@6")
            == .estimate(315, basis: try basis("315x5@7", .history(block27W1D2)))
    )
}

@Test func aTieInRPEGoesToTheLaterSetLog() throws {
    #expect(
        suggest(history: "300x5@8, 290x5@8")
            == .estimate(290, basis: try basis("290x5@8", .history(block27W1D2)))
    )
}

@Test func aSkipInTheEntryLeavesItsSetLogsUsable() throws {
    #expect(suggest(history: "skip, 315x5@7") == .estimate(325, basis: try basis("315x5@7", .history(block27W1D2))))
}

@Test func aPercentOneRMWithATrainingMaxBeatsHistory() {
    #expect(suggest(percentOneRM: "75%", trainingMax: 400, history: "315x5@7") == .prescribedWeight(300))
}

@Test func aRepRangeTargetsItsMidpoint() throws {
    let basis = try basis("315x5@7", .history(block27W1D2))

    #expect(suggest(reps: "8-10", history: "315x5@7") == .estimate(282.5, basis: basis))
    #expect(suggest(reps: "7 - 8", history: "315x5@7") == .estimate(300, basis: basis))
    #expect(suggest(reps: "7 – 8", history: "315x5@7") == .estimate(300, basis: basis))
}

@Test(
    "A history entry with no usable Set Log suggests nothing",
    arguments: [
        "BWx5@7",
        "felt heavy",
        "skip",
        "55x8, 60x7@9.5",
        "315x13@7",
        "315x5@5",
        "0x5@7"
    ]
)
func aHistoryEntryWithNoUsableSetLogSuggestsNothing(resultText: String) {
    #expect(suggest(history: resultText) == .noSuggestion)
}

@Test func anEntryWithOneUnstructuredSetLogSuppliesNoBasis() {
    #expect(suggest(history: "315x5@7, 315x5") == .noSuggestion)
}

@Test func aSingleAtRPE10IsTheTablesTopPoint() throws {
    #expect(
        suggest(reps: "1", load: "RPE10", history: "100x1@10")
            == .estimate(100, basis: try basis("100x1@10", .history(block27W1D2)))
    )
}

@Test func twelveRepsAtRPE6IsTheTablesBottomPointAt57Point4Percent() throws {
    #expect(
        suggest(reps: "1", load: "RPE10", history: "287x12@6")
            == .estimate(500, basis: try basis("287x12@6", .history(block27W1D2)))
    )
    #expect(
        suggest(reps: "12", load: "RPE6", history: "100x1@10")
            == .estimate(57.5, basis: try basis("100x1@10", .history(block27W1D2)))
    )
}

@Test func aSetLogWithTheLargestRepCountSuggestsNothing() throws {
    let largest = "100x9223372036854775807@8"
    #expect(try setLog(largest).reps == .max)

    #expect(suggest(history: largest) == .noSuggestion)
}

@Test(
    "A target the RPE Table cannot place suggests nothing",
    arguments: [
        ("13", "RPE8"), ("10-15", "RPE8"), ("4-14", "RPE8"), ("0-12", "RPE8"), ("AMRAP", "RPE8"), ("5+", "RPE8"), ("40 sec", "RPE7"),
        ("5", "RPE5")
    ]
)
func aTargetTheRPETableCannotPlaceSuggestsNothing(reps: String, load: String) {
    #expect(suggest(reps: reps, load: load, history: "315x5@7") == .noSuggestion)
}

@Test func anEntryFromAnUnrecognizedSourceSuggestsNothing() {
    let legacySource = LastPerformedOccurrence(
        fullName: "Back Squat",
        baseName: "Back Squat",
        resultText: "315x5@7",
        performedOn: Date(timeIntervalSinceReferenceDate: 0),
        source: "W1 D2"
    )

    #expect(
        LoadSuggestionEngine.suggest(
            LoadSuggestionInputs(
                prescribedReps: "5",
                prescribedLoad: "RPE8",
                percentOneRM: nil,
                trainingMax: nil,
                earlierSets: [],
                lastPerformed: legacySource
            )
        ) == .noSuggestion
    )
}
