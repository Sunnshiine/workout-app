import Foundation
import Testing

@testable import WorkoutTracker

private func entry(prefill: Double?, setNumber: Int = 1) -> WarmupEntry {
    WarmupEntry(exerciseOrder: 0, exerciseTitle: "Back Squat", setNumber: setNumber, prefill: prefill)
}

private func walkedRows(_ presentation: WarmupRampPresentation) -> [WarmupRampPresentation.RowState] {
    presentation.rows.map(\.state)
}

@Suite struct WarmupWalkTests {
    private let steps = WarmupRamp.make(top: .pounds(135), inventory: .standard)

    private func finished(_ walk: WarmupWalk) -> Int {
        walk.finishedCount(of: steps, forExerciseOrder: 0)
    }

    @Test func aWalkStartsOnTheFirstStep() {
        #expect(finished(WarmupWalk()) == 0)
    }

    @Test func tappingTheCurrentStepFinishesItAlone() {
        var walk = WarmupWalk()
        walk.tap(rowAt: 0, of: steps, forExerciseOrder: 0)
        #expect(finished(walk) == 1)
        walk.tap(rowAt: 1, of: steps, forExerciseOrder: 0)
        #expect(finished(walk) == 2)
    }

    @Test func tappingAStepAheadFinishesEveryStepUpToIt() {
        var walk = WarmupWalk()
        walk.tap(rowAt: 2, of: steps, forExerciseOrder: 0)
        #expect(finished(walk) == 3)
    }

    @Test func tappingAFinishedStepPutsTheWalkBackOnIt() {
        var walk = WarmupWalk()
        walk.tap(rowAt: 3, of: steps, forExerciseOrder: 0)
        walk.tap(rowAt: 1, of: steps, forExerciseOrder: 0)
        #expect(finished(walk) == 1)
        walk.tap(rowAt: 0, of: steps, forExerciseOrder: 0)
        #expect(finished(walk) == 0)
    }

    @Test func tappingTheSetFinishesEveryStepAndStaysThere() {
        var walk = WarmupWalk()
        walk.tap(rowAt: steps.count, of: steps, forExerciseOrder: 0)
        #expect(finished(walk) == steps.count)
        walk.tap(rowAt: steps.count, of: steps, forExerciseOrder: 0)
        #expect(finished(walk) == steps.count)
    }

    @Test func eachExerciseWalksOnItsOwn() {
        var walk = WarmupWalk()
        walk.tap(rowAt: 2, of: steps, forExerciseOrder: 0)
        #expect(walk.finishedCount(of: steps, forExerciseOrder: 1) == 0)
    }

    @Test func aChangedBarKeepsWhatWasLiftedAsTheWalk() {
        var walk = WarmupWalk()
        walk.tap(rowAt: 2, of: steps, forExerciseOrder: 0)
        let onALighterBar = WarmupRamp.make(top: .pounds(135), inventory: PlateInventory.standard.withBar(.light))
        #expect(onALighterBar.map(\.load.reachable) == [35, 55, 75, 95, 115])
        #expect(walk.finishedCount(of: onALighterBar, forExerciseOrder: 0) == 3)
    }
}

@Suite struct WarmupRampPresentationTests {
    @Test func aRampOpensOnTheEmptyBarWithEveryRowAheadOfIt() {
        let presentation = WarmupRampPresentation(entry: entry(prefill: 135), inventory: .standard, walk: WarmupWalk())

        #expect(presentation.perSide.isEmpty)
        #expect(presentation.readout == "Bar")
        #expect(presentation.caption == "45 lb")
        #expect(presentation.rows.map(\.weight) == ["45", "60", "80", "95", "115", "135"])
        #expect(presentation.rows.map(\.detail) == ["× 5", "× 5", "× 3", "× 2", "× 1", "Set 1"])
        #expect(walkedRows(presentation) == [.current, .ahead, .ahead, .ahead, .ahead, .ahead])
        #expect(presentation.note == nil)
    }

    @Test func theBarShowsTheCurrentStepsLoad() {
        var walk = WarmupWalk()
        let steps = WarmupRamp.make(top: .pounds(315), inventory: .standard)
        walk.tap(rowAt: 2, of: steps, forExerciseOrder: 0)

        let presentation = WarmupRampPresentation(entry: entry(prefill: 315), inventory: .standard, walk: walk)

        #expect(presentation.perSide == [.fortyFive, .thirtyFive])
        #expect(presentation.readout == "45 + 35")
        #expect(presentation.caption == "a side")
        #expect(walkedRows(presentation) == [.finished, .finished, .finished, .current, .ahead, .ahead])
    }

    @Test func theWalkEndsOnTheSetWhichIsNeverFinished() {
        var walk = WarmupWalk()
        let steps = WarmupRamp.make(top: .pounds(135), inventory: .standard)
        walk.tap(rowAt: steps.count, of: steps, forExerciseOrder: 0)

        let presentation = WarmupRampPresentation(entry: entry(prefill: 135, setNumber: 3), inventory: .standard, walk: walk)

        #expect(presentation.readout == "45")
        #expect(presentation.rows.last?.id == "warmup-set")
        #expect(presentation.rows.last?.detail == "Set 3")
        #expect(presentation.rows.last?.state == .current)
        #expect(presentation.rows.dropLast().allSatisfy { $0.state == .finished })
    }

    @Test func aReadoutCountsEachSizeOnce() {
        #expect(WarmupRampPresentation.readout([.fortyFive, .fortyFive, .twentyFive]) == "2 × 45 + 25")
        #expect(WarmupRampPresentation.readout([.twoAndAHalf]) == "2.5")
        #expect(WarmupRampPresentation.readout([]) == "Bar")
    }

    @Test func aSetTheInventoryCannotMakeKeepsItsWeightAndSaysWhatLoads() {
        let noChange = PlateInventory(bar: .standard, plates: [.fortyFive, .twentyFive, .ten, .five])

        let presentation = WarmupRampPresentation(entry: entry(prefill: 47.5), inventory: noChange, walk: WarmupWalk())
        let set = presentation.rows.last

        #expect(presentation.rows.map(\.weight) == ["47.5"])
        #expect(set?.detail == "Set 1, loads as 45")
        #expect(set?.accessibilityLabel == "Set 1 is 47.5 pounds, loads as 45")
    }

    @Test func aSetTheInventoryMakesExactlyReadsPlainToAScreenReader() {
        let presentation = WarmupRampPresentation(entry: entry(prefill: 135), inventory: .standard, walk: WarmupWalk())

        #expect(presentation.rows.first?.accessibilityLabel == "45 pounds for 5 reps")
        #expect(presentation.rows.first?.accessibilityValue == "Current")
        #expect(presentation.rows[4].accessibilityLabel == "115 pounds for 1 rep")
        #expect(presentation.rows[4].accessibilityValue == "")
        #expect(presentation.rows.last?.accessibilityLabel == "Set 1, 135 pounds")
    }

    @Test func aFinishedStepSaysSoToAScreenReader() {
        var walk = WarmupWalk()
        walk.tap(rowAt: 0, of: WarmupRamp.make(top: .pounds(135), inventory: .standard), forExerciseOrder: 0)

        let presentation = WarmupRampPresentation(entry: entry(prefill: 135), inventory: .standard, walk: walk)

        #expect(presentation.rows.first?.accessibilityValue == "Finished")
    }

    @Test func theDrawnBarReadsAsOneSentence() {
        var walk = WarmupWalk()
        walk.tap(rowAt: 3, of: WarmupRamp.make(top: .pounds(315), inventory: .standard), forExerciseOrder: 0)

        let presentation = WarmupRampPresentation(entry: entry(prefill: 315), inventory: .standard, walk: walk)
        let empty = WarmupRampPresentation(entry: entry(prefill: 315), inventory: .standard, walk: WarmupWalk())

        #expect(presentation.barAccessibilityLabel == "2 times 45 and 10 and 5 and 2.5 a side")
        #expect(empty.barAccessibilityLabel == "Bar, 45 lb, nothing on it")
    }

    @Test func aSetWithNoTopAsksForOneAndShowsNoRows() {
        let presentation = WarmupRampPresentation(entry: entry(prefill: nil), inventory: .standard, walk: WarmupWalk())

        #expect(presentation.note == "Pick Set 1’s weight.")
        #expect(presentation.rows.isEmpty)
        #expect(presentation.perSide.isEmpty)
    }

    @Test func aPickedTopWalksLikeAPreFilledOne() {
        var walk = WarmupWalk()
        walk.pick(top: 135, forExerciseOrder: 0)

        let presentation = WarmupRampPresentation(entry: entry(prefill: nil), inventory: .standard, walk: walk)

        #expect(presentation.note == nil)
        #expect(presentation.rows.map(\.weight) == ["45", "60", "80", "95", "115", "135"])
    }

    @Test func aPreFillOutranksAnEarlierPick() {
        var walk = WarmupWalk()
        walk.pick(top: 500, forExerciseOrder: 0)

        let presentation = WarmupRampPresentation(entry: entry(prefill: 135), inventory: .standard, walk: walk)

        #expect(presentation.rows.last?.weight == "135")
    }

    @Test func aSetLighterThanTheBarHasNoWalkUntilALighterBarFitsIt() {
        let forty = entry(prefill: 40)

        #expect(!forty.hasWalk(on: .standard))
        #expect(forty.hasWalk(on: PlateInventory.standard.withBar(.light)))
    }

    @Test func aSetAtTheBarsOwnWeightStillHasAWalkOfOneRow() {
        let bar = entry(prefill: 45)

        #expect(bar.hasWalk(on: .standard))
        #expect(WarmupRampPresentation(entry: bar, inventory: .standard, walk: WarmupWalk()).rows.map(\.id) == ["warmup-set"])
    }

    @Test func aTopTheAthletePicksAlwaysHasAWalk() {
        #expect(entry(prefill: nil).hasWalk(on: .standard))
    }

    @Test func theLighterBarChangesEveryRow() {
        let lightBar = PlateInventory.standard.withBar(.light)

        let presentation = WarmupRampPresentation(entry: entry(prefill: 135), inventory: lightBar, walk: WarmupWalk())

        #expect(presentation.caption == "35 lb")
        #expect(presentation.rows.map(\.weight) == ["35", "55", "75", "95", "115", "135"])
    }
}

@Suite struct WarmupTopRailTests {
    @Test func theRailRestsOnOnePlateASideWithNothingChosen() {
        let chips = WarmupTopRail.chips(picked: nil)

        #expect(chips[WarmupTopRail.selectedIndex(picked: nil)].label == "135")
        #expect(chips.allSatisfy { !$0.isSelected })
        #expect(chips.allSatisfy { !$0.isPrescribed })
    }

    @Test func aPickIsTheOneChipSelected() {
        let chips = WarmupTopRail.chips(picked: 225)

        #expect(chips.filter(\.isSelected).map(\.label) == ["225"])
        #expect(chips[WarmupTopRail.selectedIndex(picked: 225)].label == "225")
    }
}

@Suite struct BarbellLayoutTests {
    @Test func platesStackFromTheCollarOutHeaviestFirst() {
        let layout = BarbellLayout(perSide: [.fortyFive, .twentyFive], sleeveLength: 140)

        #expect(layout.plates.map(\.id) == ["45-0", "25-0"])
        #expect(layout.plates[0].offset == 0)
        #expect(layout.plates[0].thickness == 17)
        #expect(layout.plates[0].height == 1)
        #expect(layout.plates[1].offset == 18.5)
        #expect(abs(layout.plates[1].height - 0.689) < 0.001)
    }

    @Test func aPlatesDrawnSizeFollowsItsWeight() {
        let layout = BarbellLayout(perSide: PlateDenomination.allCases, sleeveLength: 140)

        let heights = layout.plates.map(\.height)
        let thicknesses = layout.plates.map(\.thickness)
        #expect(zip(heights, heights.dropFirst()).allSatisfy { $0 > $1 })
        #expect(zip(thicknesses, thicknesses.dropFirst()).allSatisfy { $0 > $1 })
        #expect(abs(heights[5] - 0.339) < 0.001)
        #expect(abs(thicknesses[5] - 4.96) < 0.01)
    }

    @Test func aSecondPlateOfASizeKeepsTheFirstsIdentity() {
        let one = BarbellLayout(perSide: [.fortyFive], sleeveLength: 140)
        let two = BarbellLayout(perSide: [.fortyFive, .fortyFive], sleeveLength: 140)

        #expect(two.plates.map(\.id) == ["45-0", "45-1"])
        #expect(one.plates[0].id == two.plates[0].id)
    }

    @Test func theSleeveStaysInViewPastTheHeaviestLoad() throws {
        let load = try #require(PlateLoad(weighing: 2000, on: .standard))

        let layout = BarbellLayout(perSide: load.perSide, sleeveLength: 140)

        let last = try #require(layout.plates.last)
        #expect(abs(last.offset + last.thickness - 126) < 0.001)
    }

    @Test func aBarAloneHasNoPlates() {
        #expect(BarbellLayout(perSide: [], sleeveLength: 140).plates.isEmpty)
    }
}

@MainActor
@Suite struct WarmupEntryTests {
    private func exercise(_ sets: [ExerciseSet], name: String = "Back Squat", order: Int = 0) -> Exercise {
        let exercise = Exercise(name: ExerciseName(entered: name), coachNote: nil, order: order)
        exercise.sets = sets
        return exercise
    }

    private func pending(_ index: Int, reps: String = "5", load: String = "RPE8") -> ExerciseSet {
        ExerciseSet(index: index, prescribedReps: reps, prescribedLoad: load, percentOneRM: nil, state: .pending)
    }

    private func logged(_ index: Int, _ pounds: Double) -> ExerciseSet {
        let set = ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil, state: .logged)
        set.setLog = SetLog(weight: .pounds(pounds), reps: 5, rpe: .eight)
        return set
    }

    @Test func theEntryIsForTheFirstPendingSetOfTheExerciseOnStage() throws {
        let stage = makeStage([exercise([logged(0, 225), pending(1)])])

        let entry = try #require(stage.queue.warmupEntry)

        #expect(entry.exerciseTitle == "Back Squat")
        #expect(entry.setNumber == 2)
        #expect(entry.prefill == 225)
    }

    @Test func aSetWithNoPreFillLeavesTheTopToTheAthlete() throws {
        let entry = try #require(makeStage([exercise([pending(0)])]).queue.warmupEntry)

        #expect(entry.prefill == nil)
        #expect(entry.setNumber == 1)
    }

    @Test func aBodyweightSetOffersNoRamp() {
        #expect(makeStage([exercise([pending(0, load: "BW")])]).queue.warmupEntry == nil)
    }

    @Test func aTimedSetOffersNoRamp() {
        #expect(makeStage([exercise([pending(0, reps: "40 sec")])]).queue.warmupEntry == nil)
    }

    @Test func aFinishedExerciseOffersNoRamp() {
        #expect(makeStage([exercise([logged(0, 225)])]).queue.warmupEntry == nil)
    }

    @Test func aSupersetOffersTheRampOfTheExerciseInFocus() throws {
        let squat = exercise([pending(0)])
        let row = exercise([pending(0)], name: "DB Row", order: 1)
        let superset = Superset(first: squat, second: row)

        let onRow = makeStage(
            [squat, row],
            focus: .activeSet(ActiveSetID(exerciseOrder: 1, setIndex: 0)),
            supersets: [superset]
        )

        #expect(try #require(onRow.queue.warmupEntry).exerciseTitle == "DB Row")
    }
}
