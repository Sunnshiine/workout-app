import Testing

@testable import WorkoutTracker

@Suite struct WarmupRampTests {
    private func walk(_ top: Weight, _ inventory: PlateInventory = .standard) -> [String] {
        WarmupRamp.make(top: top, inventory: inventory).map { "\(Weight.pounds($0.load.reachable).label)x\($0.reps)" }
    }

    @Test func oneThirtyFiveWalksInEighteenPoundJumpsRoundedDown() {
        #expect(walk(.pounds(135)) == ["45x5", "60x5", "80x3", "95x2", "115x1"])
    }

    @Test func eachStepCarriesItsPlateLoad() {
        let steps = WarmupRamp.make(top: .pounds(135), inventory: .standard)
        #expect(
            steps.map(\.load.perSide) == [
                [],
                [.five, .twoAndAHalf],
                [.ten, .five, .twoAndAHalf],
                [.twentyFive],
                [.thirtyFive]
            ]
        )
    }

    @Test func threeFifteenTapersFiveFiveThreeTwoOne() {
        #expect(walk(.pounds(315)) == ["45x5", "95x5", "150x3", "205x2", "260x1"])
    }

    @Test func aThousandAndFiveStillWalksFiveJumps() {
        #expect(walk(.pounds(1005)) == ["45x5", "235x5", "425x3", "620x2", "810x1"])
    }

    @Test func aRoundedDownJumpThatLandsOnAnEarlierStepDropsOutAndTheEarlierKeepsItsReps() {
        #expect(walk(.pounds(65)) == ["45x5", "50x3", "55x2", "60x1"])
    }

    @Test func aJumpThatRoundsOntoTheTopDropsOut() {
        #expect(walk(.pounds(50)) == ["45x5"])
    }

    @Test func aTopTheBarAloneMakesHasNoStepsBelowIt() {
        #expect(walk(.pounds(45)).isEmpty)
        #expect(walk(.pounds(47.5)).isEmpty)
    }

    @Test func aTopLighterThanTheBarHasNoRamp() {
        #expect(walk(.pounds(30)).isEmpty)
    }

    @Test func bodyweightHasNoRamp() {
        #expect(walk(.bodyweight).isEmpty)
    }

    @Test func theBarChangesEveryJump() {
        let light = PlateInventory(bar: .light, plates: Set(PlateDenomination.allCases))
        #expect(walk(.pounds(135), light) == ["35x5", "55x5", "75x3", "95x2", "115x1"])
    }

    @Test func aGymWithOnlyFortyFivesWalksInWholePlates() {
        let fortyFives = PlateInventory(bar: .standard, plates: [.fortyFive])
        #expect(walk(.pounds(315), fortyFives) == ["45x5", "135x3", "225x1"])
    }

    @Test func aGymWithNoPlatesHasOnlyTheBar() {
        let none = PlateInventory(bar: .standard, plates: [])
        #expect(walk(.pounds(315), none).isEmpty)
    }
}

@MainActor
@Suite struct WarmupTopTests {
    private func set(reps: String, load: String, state: SetState = .pending, setLog: SetLog? = nil) -> ExerciseSet {
        let exercise = Exercise(name: ExerciseName(entered: "Back Squat"), coachNote: nil, order: 0)
        let set = ExerciseSet(index: 0, prescribedReps: reps, prescribedLoad: load, percentOneRM: nil, state: state)
        set.setLog = setLog
        exercise.sets = [set]
        return set
    }

    @Test func aPendingSetWithNoWeightToStartFromLetsTheAthletePick() {
        #expect(WarmupTop(for: set(reps: "5", load: "RPE8"), history: .empty) == .athletePicks)
        #expect(WarmupTop(for: set(reps: "5", load: "Start conservative"), history: .empty) == .athletePicks)
    }

    @Test func aBodyweightSetIsBodyweight() {
        #expect(WarmupTop(for: set(reps: "12", load: "BW"), history: .empty) == .bodyweight)
    }

    @Test func aLoggedSetWalksToItsOwnWeight() {
        let logged = set(reps: "5", load: "RPE8", state: .logged, setLog: SetLog(weight: .pounds(1005), reps: 1, rpe: RPE(rawValue: 9)!))
        #expect(WarmupTop(for: logged, history: .empty) == .weight(1005))
    }

    @Test func aLoggedBodyweightSetIsBodyweight() {
        let logged = set(reps: "12", load: "BW", state: .logged, setLog: SetLog(weight: .bodyweight, reps: 12, rpe: RPE(rawValue: 7)!))
        #expect(WarmupTop(for: logged, history: .empty) == .bodyweight)
    }

    @Test func aPreFillPastAnythingABarHoldsLetsTheAthletePick() {
        let typo = set(reps: "5", load: "RPE8", state: .logged, setLog: SetLog(weight: .pounds(99_999), reps: 1, rpe: RPE(rawValue: 9)!))
        #expect(WarmupTop(for: typo, history: .empty) == .athletePicks)
    }

    @Test func aTimedSetHasNoTopButAnOpeningHoldStillLoadsTheBar() {
        #expect(WarmupTop(for: set(reps: "40 sec", load: "RPE8"), history: .empty) == .timedSet)

        let exercise = Exercise(name: ExerciseName(entered: "BB RDL"), coachNote: "Start w/ 10 sec hold, proceed to rep range.", order: 0)
        let held = ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE8", percentOneRM: nil, state: .pending)
        held.setLog = SetLog(weight: .pounds(225), reps: 8, rpe: RPE(rawValue: 8)!)
        exercise.sets = [held]
        #expect(WarmupTop(for: held, history: .empty) == .weight(225))
    }
}
