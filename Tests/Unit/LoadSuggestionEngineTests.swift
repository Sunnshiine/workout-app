import Foundation
import Testing

@testable import WorkoutTracker

/// The engine's inputs as the old four-argument call named them: a `previousSetWeight` is the one
/// Set logged just before this one.
private func suggest(
    prescribedLoad: String,
    percentOneRM: String?,
    previousSetWeight: Double?,
    trainingMax: Double?
) -> LoadSuggestion {
    LoadSuggestionEngine.suggest(
        LoadSuggestionInputs(
            prescribedReps: "5",
            prescribedLoad: prescribedLoad,
            percentOneRM: percentOneRM,
            trainingMax: trainingMax,
            earlierSets: previousSetWeight.map { [(index: 0, setLog: SetLog(weight: .pounds($0), reps: 5, rpe: .eight))] } ?? [],
            lastPerformed: nil
        )
    )
}

private func dropSuggestion(after earlierSets: [(index: Int, setLog: SetLog)]) -> LoadSuggestion {
    LoadSuggestionEngine.suggest(
        LoadSuggestionInputs(
            prescribedReps: "5",
            prescribedLoad: "Drop 20%",
            percentOneRM: nil,
            trainingMax: nil,
            earlierSets: earlierSets,
            lastPerformed: nil
        )
    )
}

private func logged(_ weight: Weight) -> SetLog {
    SetLog(weight: weight, reps: 5, rpe: .eight)
}

@Test func suggestsLoadForDropPrescriptionFromPreviousSetWeight() {
    #expect(
        suggest(
            prescribedLoad: "Drop 17.5%",
            percentOneRM: nil,
            previousSetWeight: 225,
            trainingMax: nil
        ) == .weight(185)
    )
}

@Test func suggestsLoadForPercentOneRMPrescriptionFromTrainingMax() {
    #expect(
        suggest(
            prescribedLoad: "RPE6",
            percentOneRM: "75%",
            previousSetWeight: nil,
            trainingMax: 265
        ) == .weight(200)
    )
}

@Test func roundsLoadSuggestionToNearestPlateIncrement() {
    #expect(
        suggest(
            prescribedLoad: "Drop 12%",
            percentOneRM: nil,
            previousSetWeight: 185,
            trainingMax: nil
        ) == .weight(162.5)
    )
}

@Test func bodyweightPrescriptionPreFillsBodyweight() {
    #expect(
        suggest(
            prescribedLoad: "BW",
            percentOneRM: nil,
            previousSetWeight: nil,
            trainingMax: nil
        ) == .bodyweight
    )
}

@Test func bodyweightWinsOverAPresentPercentOneRM() {
    #expect(
        suggest(
            prescribedLoad: "BW",
            percentOneRM: "75%",
            previousSetWeight: nil,
            trainingMax: 265
        ) == .bodyweight
    )
}

@Test("Unsupported Prescribed Load returns no Load Suggestion", arguments: ["RPE 5", "Start conservative"])
func unsupportedPrescribedLoadReturnsNone(prescribedLoad: String) {
    #expect(
        suggest(
            prescribedLoad: prescribedLoad,
            percentOneRM: nil,
            previousSetWeight: 225,
            trainingMax: 265
        ) == .noSuggestion
    )
}

@Test func missingContextReturnsNoneForLoadSuggestion() {
    #expect(
        suggest(
            prescribedLoad: "Drop 17.5%",
            percentOneRM: nil,
            previousSetWeight: nil,
            trainingMax: 265
        ) == .noSuggestion
    )
    #expect(
        suggest(
            prescribedLoad: "RPE6",
            percentOneRM: "75%",
            previousSetWeight: nil,
            trainingMax: nil
        ) == .noSuggestion
    )
}

@Test func dropReadsTheNearestEarlierSetByIndexInAnyOrder() {
    #expect(dropSuggestion(after: [(index: 1, setLog: logged(.pounds(225))), (index: 0, setLog: logged(.pounds(185)))]) == .weight(180))
}

@Test func dropPassesOverABodyweightSetToTheNextOneBack() {
    #expect(dropSuggestion(after: [(index: 0, setLog: logged(.pounds(185))), (index: 1, setLog: logged(.bodyweight))]) == .weight(147.5))
}

@Test func dropOnTheFirstSetHasNothingToDropFrom() {
    #expect(dropSuggestion(after: []) == .noSuggestion)
}

// MARK: - The RPE Table arm

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

private func rpeTarget(
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

/// 315x5@7 sits at 8 effective reps (78.6%), an Estimated Single of 400.76; 5 @8 sits at 7 (81.1%),
/// 325.02, which rounds to 325.
@Test func aHistorySetLogEstimatesAHarderTargetThroughTheRPETable() throws {
    #expect(rpeTarget(history: "315x5@7") == .estimate(325, basis: try basis("315x5@7", .history(block27W1D2))))
}

@Test func anEarlierSetTodayIsTheBasisBeforeAnyHistory() throws {
    #expect(
        rpeTarget(today: [(index: 0, setLog: try setLog("315x5@7"))], history: "405x5@7")
            == .estimate(325, basis: try basis("315x5@7", .today(setIndex: 0)))
    )
}

@Test func anUnusableNearerSetTodayIsPassedOverForAnEarlierUsableOne() throws {
    let today = [(index: 0, setLog: try setLog("315x5@7")), (index: 1, setLog: try setLog("BWx5@8"))]

    #expect(rpeTarget(today: today) == .estimate(325, basis: try basis("315x5@7", .today(setIndex: 0))))
}

/// A harder Set 1 today lowers the next Set: 315x5@8.5 sits at 6.5 effective reps (82.4%).
@Test func aSetThatRanHarderTodayLowersTheNextSet() throws {
    #expect(
        rpeTarget(load: "RPE7", today: [(index: 0, setLog: try setLog("315x5@8.5"))], history: "315x5@7")
            == .estimate(300, basis: try basis("315x5@8.5", .today(setIndex: 0)))
    )
}

/// The ramp's last Set is its hardest, but a back-off after the top Set must not become the basis.
@Test func theHistoryBasisIsTheEntrysHighestRPESetLog() throws {
    #expect(
        rpeTarget(load: "RPE7", history: "315x5@7, 295x5@6")
            == .estimate(315, basis: try basis("315x5@7", .history(block27W1D2)))
    )
}

@Test func aTieInRPEGoesToTheLaterSetLog() throws {
    #expect(
        rpeTarget(history: "300x5@8, 290x5@8")
            == .estimate(290, basis: try basis("290x5@8", .history(block27W1D2)))
    )
}

@Test func aSkipInTheEntryLeavesItsSetLogsUsable() throws {
    #expect(rpeTarget(history: "skip, 315x5@7") == .estimate(325, basis: try basis("315x5@7", .history(block27W1D2))))
}

@Test func aPercentOneRMWithATrainingMaxBeatsHistory() {
    #expect(rpeTarget(percentOneRM: "75%", trainingMax: 400, history: "315x5@7") == .weight(300))
}

/// `8-10` targets 9 reps @8 (11 effective, 70.7%); `7 - 8` targets 7.5 reps @8 (9.5 effective, 75.1%).
@Test func aRepRangeTargetsItsMidpoint() throws {
    let basis = try basis("315x5@7", .history(block27W1D2))

    #expect(rpeTarget(reps: "8-10", history: "315x5@7") == .estimate(282.5, basis: basis))
    #expect(rpeTarget(reps: "7 - 8", history: "315x5@7") == .estimate(300, basis: basis))
    #expect(rpeTarget(reps: "7 – 8", history: "315x5@7") == .estimate(300, basis: basis))
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
    #expect(rpeTarget(history: resultText) == .noSuggestion)
}

@Test(
    "A target the RPE Table cannot place suggests nothing",
    arguments: [
        ("13", "RPE8"), ("10-15", "RPE8"), ("4-14", "RPE8"), ("0-12", "RPE8"), ("AMRAP", "RPE8"), ("5+", "RPE8"), ("40 sec", "RPE7"),
        ("5", "RPE5")
    ]
)
func aTargetTheRPETableCannotPlaceSuggestsNothing(reps: String, load: String) {
    #expect(rpeTarget(reps: reps, load: load, history: "315x5@7") == .noSuggestion)
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
