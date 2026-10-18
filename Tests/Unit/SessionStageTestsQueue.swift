import Foundation
import Testing

@testable import WorkoutTracker

private func completionStage(_ stage: SessionStage) -> CompletionStage? {
    guard case .complete(let completion) = stage.focus else { return nil }
    return completion
}

extension SessionStageTests {
    @Test func upNextIsTheNextIncompleteItemAfterTheStage() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.logged])
        let row = makeExercise(name: "DB Row", order: 2, setStates: [.pending, .pending])

        let upNext = try #require(makeStage([squat, bench, row]).upNext)

        #expect(upNext.title == "DB Row")
        #expect(upNext.target === row.sets.first { $0.index == 0 })
    }

    @Test func upNextWrapsAroundToEarlierIncompleteItems() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.logged])
        let row = makeExercise(name: "DB Row", order: 2, setStates: [.pending])

        let stage = makeStage([squat, bench, row], focus: .activeSet(ActiveSetID(exerciseOrder: 2, setIndex: 0)))

        #expect(stage.upNext?.title == "Squat")
        #expect(stage.upNext?.target === squat.sets.first)
    }

    @Test func upNextIsNilWhenNoOtherItemRemains() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])

        #expect(makeStage([squat, bench]).upNext == nil)
        #expect(makeStage([squat]).upNext == nil)
    }

    @Test func titlesReadTheBaseNameWithoutTheCadencePrefix() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let rdl = Exercise(name: "2-3:1:0 BB RDL", coachNote: nil, order: 1)
        rdl.sets = [ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)]

        let stage = makeStage([squat, rdl])

        #expect(stage.upNext?.title == "BB RDL")
        #expect(stage.queue.rows.map(\.title) == ["Squat", "BB RDL"])
    }

    @Test func thePillCountsThePlaceOfTheItemOnStage() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let press = makeExercise(name: "Press", order: 1, setStates: [.pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending])

        let first = makeStage([squat, press, row]).queue.position
        let second = makeStage([squat, press, row], focus: .activeSet(ActiveSetID(exerciseOrder: 2, setIndex: 0))).queue.position
        let superset = makeStage(
            [squat, press, row],
            focus: .activeSet(ActiveSetID(exerciseOrder: 2, setIndex: 0)),
            supersets: [Superset(first: press, second: row)]
        ).queue.position

        #expect(first.label == "1 of 3")
        #expect(second.label == "3 of 3")
        #expect(superset.label == "2 of 2")
    }

    @Test func thePillOfACompleteSessionReadsAsTheLastPlace() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let rdl = makeExercise(name: "BB RDL", order: 1, setStates: [.skipped])

        #expect(makeStage([squat, rdl]).queue.position.label == "2 of 2")
    }

    @Test func everySetResolvedIsTheCompletionStage() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .logged])
        let press = makeExercise(name: "Press", order: 1, setStates: [.logged, .skipped])
        let row = makeExercise(name: "Row", order: 2, setStates: [.skipped])

        let stage = makeStage([squat, press, row])

        #expect(try #require(completionStage(stage)).summary == "5 sets done across 3 exercises")
        #expect(stage.upNext == nil)
        #expect(stage.queue.rows.map(\.isComplete) == [true, true, true])
        #expect(stage.queue.rows.map(\.isOnStage) == [false, false, false])
    }

    @Test func theCompletionSummaryUsesSingularForms() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])

        #expect(try #require(completionStage(makeStage([squat]))).summary == "1 set done across 1 exercise")
    }

    @Test func moveOnAndTheOpenExercisesShowAtTheLiveEdge() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let makeup = makeExercise(name: "Front Squat", order: 0, setStates: [.pending])

        let stage = makeStage([squat], liveEdge: .atLiveEdge(canMoveOn: true, openExercises: [makeup]))

        let completion = try #require(completionStage(stage))
        #expect(completion.showsMoveOn)
        #expect(completion.openExercises == [makeup])
        #expect(stage.queue.showsMoveOn)
        #expect(stage.queue.openExercises == [makeup])
    }

    @Test func theLiveEdgeKeepsTheOpenExercisesWhenMoveOnIsNotOffered() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let makeup = makeExercise(name: "Front Squat", order: 0, setStates: [.pending])

        let stage = makeStage([squat], liveEdge: .atLiveEdge(canMoveOn: false, openExercises: [makeup]))

        let completion = try #require(completionStage(stage))
        #expect(!completion.showsMoveOn)
        #expect(completion.openExercises == [makeup])
        #expect(!stage.queue.showsMoveOn)
    }

    @Test func aSessionBrowsedAwayFromOffersNeitherMoveOnNorTheOpenExercises() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])

        let complete = makeStage([squat], liveEdge: .browsedAway)
        let inProgress = makeStage([squat, bench], liveEdge: .browsedAway)

        let completion = try #require(completionStage(complete))
        #expect(!completion.showsMoveOn)
        #expect(completion.openExercises.isEmpty)
        #expect(!inProgress.queue.showsMoveOn)
        #expect(inProgress.queue.openExercises.isEmpty)
    }

    @Test func noRowHasAPairingRoleWhilePairingIsInactive() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])

        let queue = makeStage([squat, bench], pairable: [0, 1]).queue

        #expect(!queue.isPairing)
        #expect(queue.rows.map(\.pairingRole) == [QueuePairingRole.none, .none])
    }

    @Test func eachRowNamesItsKind() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let press = makeExercise(name: "Press", order: 2, setStates: [.pending])
        let row = makeExercise(name: "Row", order: 3, setStates: [.pending])

        let queue = makeStage([squat, bench, press, row], supersets: [Superset(first: press, second: row)], pairable: [1, 2]).queue

        #expect(queue.rows.map(\.id) == ["exercise-0", "exercise-1", "superset-2"])
        #expect(queue.rows.map(\.kind) == [.exercise, .pairableExercise, .superset])
    }

    @Test func theSupersetSourceIsTheOnStageRowWhenItCanPair() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let press = makeExercise(name: "Press", order: 2, setStates: [.pending])
        let pressFocus = ActiveSetVisualFocusOwner.activeSet(ActiveSetID(exerciseOrder: 2, setIndex: 0))

        let onPress = makeStage([squat, bench, press], focus: pressFocus, pairable: [1, 2]).queue
        let onUnpairableBench = makeStage([squat, bench, press], pairable: [2]).queue

        #expect(onPress.supersetSource?.id == "exercise-2")
        #expect(onUnpairableBench.supersetSource == nil)
    }

    @Test func aSupersetOnStageOffersNoSupersetSource() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let press = makeExercise(name: "Press", order: 2, setStates: [.pending])
        let row = makeExercise(name: "Row", order: 3, setStates: [.pending])

        let queue = makeStage([squat, bench, press, row], supersets: [Superset(first: bench, second: press)], pairable: [1, 2, 3]).queue

        #expect(queue.rows.map(\.isOnStage) == [false, true, false])
        #expect(queue.supersetSource == nil)
    }

    @Test func selectingMarksTheSourceAndEachTargetsEligibility() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let carry = makeExercise(name: "Farmer Carry", order: 2, setStates: [.logged])

        let queue = makeStage([squat, bench, carry], pairable: [0, 1], pairingMode: .selecting(sourceOrder: 0)).queue

        #expect(queue.isPairing)
        #expect(queue.pairingMode == .selecting(sourceOrder: 0))
        #expect(queue.rows.map(\.pairingRole) == [.source, .eligibleTarget, .ineligibleTarget])
    }

    @Test func thePairingSourceIsTheSourceRowOnlyWhilePairing() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])

        let selecting = makeStage([squat, bench], pairable: [0, 1], pairingMode: .selecting(sourceOrder: 1)).queue
        let inactive = makeStage([squat, bench], pairable: [0, 1]).queue

        #expect(selecting.pairingSource?.id == "exercise-1")
        #expect(inactive.pairingSource == nil)
    }

    @Test func confirmingMarksTheConfirmingTarget() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])

        let queue = makeStage(
            [squat, bench],
            pairable: [0, 1],
            pairingMode: .confirming(sourceOrder: 0, targetOrder: 1)
        ).queue

        #expect(queue.rows.map(\.pairingRole) == [.source, .confirmingTarget])
    }

    @Test func aSupersetRowIsNeverAPairingTarget() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let press = makeExercise(name: "Press", order: 1, setStates: [.pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending])

        let queue = makeStage(
            [squat, press, row],
            supersets: [Superset(first: press, second: row)],
            pairable: [0, 1, 2],
            pairingMode: .selecting(sourceOrder: 0)
        ).queue

        #expect(queue.rows.map(\.pairingRole) == [.source, .ineligibleTarget])
    }
}
