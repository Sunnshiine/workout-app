import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func makeStage(
    _ exercises: [Exercise],
    active: ActiveSetID? = nil,
    expanded: ActiveSetID? = nil,
    saved: ActiveSetID? = nil,
    supersets: [Superset] = [],
    pairable: Set<Int> = [],
    pairingMode: PairingMode = .inactive,
    liveEdge: LiveEdgeContext = .browsedAway,
    lookup: LastPerformedLookupSnapshot = .empty
) -> SessionStage {
    let session = Session(dayNumber: 1, date: nil)
    session.exercises = exercises
    return SessionStage(
        session: session,
        focus: SessionFocusSnapshot(
            activeSetID: active,
            expandedLoggedSetID: expanded,
            supersets: supersets,
            pairableExerciseOrders: pairable
        ),
        savedLoggedSetID: saved,
        pairingMode: pairingMode,
        liveEdge: liveEdge,
        lookup: lookup
    )
}

private func exerciseStage(_ stage: SessionStage) -> ExerciseStage? {
    guard case .exercise(let exercise) = stage.focus else { return nil }
    return exercise
}

private func supersetStage(_ stage: SessionStage) -> SupersetStage? {
    guard case .superset(let superset) = stage.focus else { return nil }
    return superset
}

private func completionStage(_ stage: SessionStage) -> CompletionStage? {
    guard case .complete(let completion) = stage.focus else { return nil }
    return completion
}

private func benchHistory() -> LastPerformedLookupSnapshot {
    LastPerformedLookupSnapshot(
        occurrences: [
            LastPerformedOccurrence(
                fullName: "Bench Press",
                baseName: "Bench Press",
                resultText: "185x6@7",
                performedOn: Date(timeIntervalSinceReferenceDate: 100),
                source: "W3 D2"
            )
        ]
    )
}

@MainActor
@Suite("SessionStage")
struct SessionStageTests {
    @Test func aSupersetFusesAtItsLowerOrderedSideAndTheRestKeepSessionOrder() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let press = makeExercise(name: "Press", order: 1, setStates: [.pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending])
        let carry = makeExercise(name: "Farmer Carry", order: 3, setStates: [.pending])

        let stage = makeStage([carry, row, squat, press], supersets: [Superset(first: carry, second: press)])

        #expect(stage.queue.rows.map(\.id) == ["exercise-0", "superset-1", "exercise-2"])
        #expect(stage.queue.rows.map(\.title) == ["Squat", "Farmer Carry + Press", "Row"])
        #expect(stage.queue.rows[1].pairingExercise === carry)
    }

    @Test func theStageFollowsFocusIntoItsOwningItem() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending, .pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])

        let stage = makeStage([squat, bench], active: ActiveSetID(exerciseOrder: 1, setIndex: 0))

        #expect(try #require(exerciseStage(stage)).exercise === bench)
        #expect(stage.queue.rows.map(\.isOnStage) == [false, true])
    }

    @Test func theStageFallsBackToTheFirstIncompleteItemWithoutFocus() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.skipped, .pending])
        let row = makeExercise(name: "DB Row", order: 2, setStates: [.pending])

        let stage = makeStage([squat, bench, row])

        #expect(try #require(exerciseStage(stage)).exercise === bench)
        #expect(stage.queue.rows.map(\.isOnStage) == [false, true, false])
    }

    @Test func aLoggedSetOpenForReviewPutsItsExerciseOnStage() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])

        let stage = makeStage(
            [squat, bench],
            active: ActiveSetID(exerciseOrder: 1, setIndex: 0),
            expanded: ActiveSetID(exerciseOrder: 0, setIndex: 0)
        )

        let onStage = try #require(exerciseStage(stage))
        #expect(onStage.exercise === squat)
        #expect(onStage.branch.activeSetID == nil)
    }

    @Test func anExerciseWithNoSetsIsOnStageWithNoCard() throws {
        let empty = makeExercise(name: "Squat", order: 0, setStates: [])

        let stage = makeStage([empty])

        let onStage = try #require(exerciseStage(stage))
        #expect(onStage.card == nil)
        #expect(!stage.queue.rows[0].isComplete)
        #expect(stage.queue.rows[0].jumpTarget == nil)
    }

    @Test func theCardHoldsTheActiveSetOverTheFirstPendingSet() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending, .pending, .pending])

        let stage = makeStage([squat], active: ActiveSetID(exerciseOrder: 0, setIndex: 2))

        let card = try #require(exerciseStage(stage)?.card)
        #expect(card.set === squat.sets.first { $0.index == 2 })
        #expect(card.ordinal == 3)
        #expect(card.count == 3)
        #expect(card.mode == .logging)
        #expect(card.cardIdentity == "stage-active-0-2")
    }

    @Test func theCardSkipsSettledSetsToTheFirstPendingSetWithoutAnActiveSet() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .skipped, .pending, .pending])

        let stage = makeStage([squat])

        let card = try #require(exerciseStage(stage)?.card)
        #expect(card.set === squat.sets.first { $0.index == 2 })
        #expect(card.ordinal == 3)
        #expect(card.cardIdentity == "stage-active-0-2")
    }

    @Test func theCardHoldsAnActiveSetThatIsAlreadyLogged() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])

        let stage = makeStage([squat, bench], active: ActiveSetID(exerciseOrder: 0, setIndex: 0))

        let card = try #require(exerciseStage(stage)?.card)
        #expect(card.set === squat.sets.first { $0.index == 0 })
        #expect(card.mode == .logging)
        #expect(card.cardIdentity == "stage-active-0-0")
    }

    @Test func aLoggedSetOpenForReviewTakesTheCard() throws {
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.logged, .pending])

        let stage = makeStage(
            [bench],
            active: ActiveSetID(exerciseOrder: 1, setIndex: 1),
            expanded: ActiveSetID(exerciseOrder: 1, setIndex: 0)
        )

        let card = try #require(exerciseStage(stage)?.card)
        #expect(card.set === bench.sets.first { $0.index == 0 })
        #expect(card.ordinal == 1)
        #expect(card.mode == .reviewingLogged(showsSavedConfirmation: false))
        #expect(card.cardIdentity == "stage-review-1-0")
        #expect(exerciseStage(stage)?.branch.activeSetID == nil)
    }

    @Test func theReviewCardConfirmsASaveOnlyForTheSetJustSaved() throws {
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.logged, .logged, .pending])
        let firstSetID = ActiveSetID(exerciseOrder: 1, setIndex: 0)

        let savedHere = makeStage([bench], expanded: firstSetID, saved: firstSetID)
        let savedElsewhere = makeStage([bench], expanded: firstSetID, saved: ActiveSetID(exerciseOrder: 1, setIndex: 1))

        #expect(exerciseStage(savedHere)?.card?.mode == .reviewingLogged(showsSavedConfirmation: true))
        #expect(exerciseStage(savedElsewhere)?.card?.mode == .reviewingLogged(showsSavedConfirmation: false))
    }

    @Test func theExerciseStageCarriesItsLastPerformedLine() throws {
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])

        let stage = makeStage([bench], lookup: benchHistory())

        let lastPerformed = try #require(exerciseStage(stage)?.lastPerformed)
        #expect(lastPerformed.resultText == "185x6@7")
        #expect(lastPerformed.sourceText == "W3 D2")
    }

    @Test func theBranchInksOneLeafPerLoggedSetAndADashedLeafPerSkip() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .skipped, .pending, .pending])

        let branch = try #require(exerciseStage(makeStage([squat]))?.branch)

        #expect(branch.nodes.map(\.state) == [.leaf, .dashedLeaf, .bud, .future])
        #expect(branch.activeSetID == nil)
    }

    @Test func theBudRidesTheActiveSet() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending, .pending, .pending])
        let activeSetID = ActiveSetID(exerciseOrder: 0, setIndex: 2)

        let branch = try #require(exerciseStage(makeStage([squat], active: activeSetID))?.branch)

        #expect(branch.nodes.map(\.state) == [.future, .future, .bud])
        #expect(branch.nodes.map(\.set) == squat.sets.sorted { $0.index < $1.index })
        #expect(branch.activeSetID == activeSetID)
    }

    @Test func theBranchIsAllLeavesWhenEverySetIsLogged() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .logged])

        let branch = try #require(
            exerciseStage(makeStage([squat], active: ActiveSetID(exerciseOrder: 0, setIndex: 1)))?.branch
        )

        #expect(branch.nodes.map(\.state) == [.leaf, .leaf])
    }

    @Test func aSupersetFocusedOnItsLowerSideLeadsWithThatSide() throws {
        let press = makeExercise(name: "Press", order: 1, setStates: [.logged, .pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.logged, .skipped, .pending, .pending])

        let stage = makeStage(
            [press, row],
            active: ActiveSetID(exerciseOrder: 1, setIndex: 1),
            supersets: [Superset(first: row, second: press)],
            lookup: benchHistory()
        )

        let superset = try #require(supersetStage(stage))
        #expect(superset.focused === press)
        #expect(superset.partner === row)
        #expect(superset.branch.nodes.map(\.state) == [.leaf, .bud])
        #expect(superset.branch.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
        #expect(superset.partnerNodes.map(\.state) == [.leaf, .dashedLeaf, .future, .future])
        let card = try #require(superset.card)
        #expect(card.set === press.sets.first { $0.index == 1 })
        #expect(card.ordinal == 2)
        #expect(card.count == 2)
        #expect(card.mode == .logging)
        #expect(card.cardIdentity == "superset-active-1-1")
    }

    @Test func aSupersetFocusedOnItsHigherSideLeadsWithThatSide() throws {
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.logged, .pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending, .pending, .pending])

        let stage = makeStage(
            [bench, row],
            active: ActiveSetID(exerciseOrder: 2, setIndex: 0),
            supersets: [Superset(first: bench, second: row)],
            lookup: benchHistory()
        )

        let superset = try #require(supersetStage(stage))
        #expect(superset.focused === row)
        #expect(superset.partner === bench)
        #expect(superset.branch.nodes.map(\.state) == [.bud, .future, .future])
        #expect(superset.partnerNodes.map(\.state) == [.leaf, .future])
        #expect(superset.card?.cardIdentity == "superset-active-2-0")
        #expect(superset.card?.ordinal == 1)
        #expect(superset.card?.count == 3)
        #expect(superset.lastPerformed == nil)
        #expect(stage.queue.rows.map(\.id) == ["superset-1"])
        #expect(stage.queue.rows[0].isOnStage)
    }

    @Test func aSupersetCarriesTheFocusedSidesLastPerformedLine() throws {
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending])

        let stage = makeStage(
            [bench, row],
            active: ActiveSetID(exerciseOrder: 1, setIndex: 0),
            supersets: [Superset(first: bench, second: row)],
            lookup: benchHistory()
        )

        #expect(try #require(supersetStage(stage)).lastPerformed?.resultText == "185x6@7")
    }

    @Test func aSupersetWithoutTheActiveSetRestsOnItsLowerSidesNextPendingSet() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.logged, .pending, .pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending])

        let stage = makeStage(
            [squat, bench, row],
            expanded: ActiveSetID(exerciseOrder: 1, setIndex: 0),
            supersets: [Superset(first: row, second: bench)],
            lookup: benchHistory()
        )

        let superset = try #require(supersetStage(stage))
        #expect(superset.focused === bench)
        #expect(superset.partner === row)
        #expect(superset.branch.activeSetID == nil)
        #expect(superset.branch.nodes.map(\.state) == [.leaf, .bud, .future])
        #expect(superset.card?.set === bench.sets.first { $0.index == 1 })
        #expect(superset.card?.cardIdentity == "superset-active-1-1")
        #expect(superset.lastPerformed == nil)
    }

    @Test func aSupersetStaysOnStageWhileFocusStillNamesTheSetJustLogged() throws {
        let squat = makeExercise(name: "Back Squat", order: 0, setStates: [.logged, .pending, .pending])
        let rdl = makeExercise(name: "BB RDL", order: 1, setStates: [.pending, .pending])

        let stage = makeStage(
            [squat, rdl],
            active: ActiveSetID(exerciseOrder: 0, setIndex: 0),
            supersets: [Superset(first: squat, second: rdl)]
        )

        let superset = try #require(supersetStage(stage))
        #expect(superset.focused === squat)
        #expect(superset.card?.set === squat.sets.first { $0.index == 0 })
        #expect(superset.card?.mode == .logging)
        #expect(superset.card?.cardIdentity == "superset-active-0-0")
        #expect(superset.branch.nodes.map(\.state) == [.leaf, .bud, .future])
        #expect(stage.queue.rows.map(\.id) == ["superset-0"])
    }

    @Test func aSupersetRowWalksBothExercisesInExerciseThenSetOrder() throws {
        let press = makeExercise(name: "Press", order: 1, setStates: [.logged, .skipped, .pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending, .logged])

        let stage = makeStage(
            [row, press],
            active: ActiveSetID(exerciseOrder: 2, setIndex: 0),
            supersets: [Superset(first: press, second: row)]
        )

        let queueRow = stage.queue.rows[0]
        #expect(queueRow.title == "Press + Row")
        #expect(queueRow.sets.map(\.index) == [0, 1, 2, 0, 1])
        #expect(queueRow.sets.first === press.sets.first { $0.index == 0 })
        #expect(queueRow.sets.last === row.sets.first { $0.index == 1 })
        #expect(queueRow.jumpTarget === press.sets.first { $0.index == 2 })
        #expect(supersetStage(stage) != nil)
    }
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

        let stage = makeStage([squat, bench, row], active: ActiveSetID(exerciseOrder: 2, setIndex: 0))

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
        let rdl = Exercise(name: "2-3:1:0 BB RDL", baseName: "BB RDL", cadence: "2-3:1:0", coachNote: nil, order: 1)
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
        let second = makeStage([squat, press, row], active: ActiveSetID(exerciseOrder: 2, setIndex: 0)).queue.position
        let superset = makeStage(
            [squat, press, row],
            active: ActiveSetID(exerciseOrder: 2, setIndex: 0),
            supersets: [Superset(first: press, second: row)]
        ).queue.position

        #expect(first.label == "1 of 3")
        #expect(first.accessibilityLabel == "Queue, 1 of 3")
        #expect(second.label == "3 of 3")
        #expect(superset.label == "2 of 2")
        #expect(superset.accessibilityLabel == "Queue, 2 of 2")
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

    @Test func onlyAPairableSingleExerciseCanBeginPairing() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let press = makeExercise(name: "Press", order: 2, setStates: [.pending])
        let row = makeExercise(name: "Row", order: 3, setStates: [.pending])

        let queue = makeStage([squat, bench, press, row], supersets: [Superset(first: press, second: row)], pairable: [1, 2]).queue

        #expect(queue.rows.map(\.id) == ["exercise-0", "exercise-1", "superset-2"])
        #expect(queue.rows.map(\.canBeginPairing) == [false, true, false])
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
