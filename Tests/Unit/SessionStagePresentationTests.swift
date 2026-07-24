import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func makeExercise(
    name: String,
    order: Int,
    setStates: [SetState],
    coachNote: String? = nil
) -> Exercise {
    let exercise = Exercise(name: name, baseName: name, cadence: nil, coachNote: coachNote, order: order)
    exercise.sets = setStates.enumerated().map { index, state in
        ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: state)
    }
    return exercise
}

@MainActor
private func exerciseItem(
    _ exercise: Exercise,
    activeSetID: ActiveSetID? = nil,
    pairingAvailability: ExercisePairingAvailability = .inactive
) -> SessionRenderItem {
    .exercise(
        SessionExerciseRenderConfig(
            exercise: exercise,
            visualFocusOwner: nil,
            activeSetID: activeSetID,
            expandedLoggedSetID: nil,
            savedLoggedSetID: nil,
            activeSetTransition: nil,
            retiringTransition: nil,
            isCollapsed: false,
            showsPairingGrip: false,
            pairingAvailability: pairingAvailability,
            isPairingConfirmation: false,
            lastPerformedPresentation: nil
        )
    )
}

@MainActor
private func supersetItem(_ first: Exercise, _ second: Exercise) throws -> SessionRenderItem {
    let presentation = try #require(
        ActiveSupersetPresentation(exercises: [first, second], activeSetID: nil)
    )
    return .superset(
        SessionSupersetRenderConfig(
            presentation: presentation,
            exercises: [first, second],
            visualFocusOwner: nil,
            activeSetTransition: nil,
            retiringTransition: nil,
            lastPerformedPresentation: nil
        )
    )
}

@MainActor
private func hiddenPairedItem(_ exercise: Exercise, containerOrder: Int) -> SessionRenderItem {
    .hiddenPairedExercise(
        SessionHiddenPairedExerciseRenderConfig(exercise: exercise, containerExerciseOrder: containerOrder)
    )
}

@MainActor
@Suite("SessionStagePresentation")
struct SessionStagePresentationTests {
    @Test func itemsDropHiddenPairedEntriesAndKeepSessionOrder() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let items = SessionStagePresentation.items([
            exerciseItem(squat),
            hiddenPairedItem(bench, containerOrder: 0),
            exerciseItem(bench),
        ])

        #expect(items.map(\.id) == ["exercise-0", "exercise-1"])
    }

    @Test func stageItemFollowsFocusIntoItsOwningItem() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending, .pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let items = SessionStagePresentation.items([exerciseItem(squat), exerciseItem(bench)])

        let stage = SessionStagePresentation.stageItem(
            in: items,
            focusID: ActiveSetID(exerciseOrder: 1, setIndex: 0)
        )

        #expect(stage?.id == "exercise-1")
    }

    @Test func stageItemFallsBackToFirstIncompleteWithoutFocus() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.skipped, .pending])
        let row = makeExercise(name: "DB Row", order: 2, setStates: [.pending])
        let items = SessionStagePresentation.items(
            [exerciseItem(squat), exerciseItem(bench), exerciseItem(row)]
        )

        let stage = SessionStagePresentation.stageItem(in: items, focusID: nil)

        #expect(stage?.id == "exercise-1")
    }

    @Test func stageItemIsNilWhenEverySetIsResolved() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.skipped])
        let items = SessionStagePresentation.items([exerciseItem(squat), exerciseItem(bench)])

        #expect(SessionStagePresentation.stageItem(in: items, focusID: nil) == nil)
    }

    @Test func restingSupersetSideSelectsItsNextPendingSetViaTheSharedQuery() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .pending, .pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending, .pending])
        let presentation = try #require(
            ActiveSupersetPresentation(exercises: [squat, bench], activeSetID: nil)
        )

        let squatSide = try #require(presentation.sides.first { $0.exerciseOrder == 0 })
        let squatNextSet = try #require(SupersetState.nextPendingSet(for: squat))

        // The resting strip's "Set X of N" reflects the shared query's selection, not the first Set.
        #expect(squatNextSet.index == 1)
        #expect(squatSide.nextSetText == "Set 2 of 3")
    }

    @Test func stageIdentityTracksTheFocusedSet() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending, .pending])
        let items = SessionStagePresentation.items([exerciseItem(squat)])

        let identity = SessionStagePresentation.stageIdentity(
            in: items,
            focusID: ActiveSetID(exerciseOrder: 0, setIndex: 1)
        )

        #expect(identity == "0-1")
    }

    @Test func stageIdentityFallsBackToStageItemThenCompletion() {
        let logged = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let pending = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let inProgress = SessionStagePresentation.items([exerciseItem(logged), exerciseItem(pending)])
        let complete = SessionStagePresentation.items([exerciseItem(logged)])

        #expect(SessionStagePresentation.stageIdentity(in: inProgress, focusID: nil) == "exercise-1")
        #expect(SessionStagePresentation.stageIdentity(in: complete, focusID: nil) == "complete")
    }

    @Test func positionLabelCountsSupersetAsOneSlot() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let press = makeExercise(name: "Press", order: 1, setStates: [.pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending])
        let items = SessionStagePresentation.items(
            [exerciseItem(squat), try supersetItem(press, row)]
        )
        let superset = try #require(items.last)

        #expect(SessionStagePresentation.positionLabel(of: superset, in: items) == "Exercise 2 of 2")
    }

    @Test func upNextReturnsTheNextIncompleteItemAfterTheStage() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.logged])
        let row = makeExercise(name: "DB Row", order: 2, setStates: [.pending])
        let items = SessionStagePresentation.items(
            [exerciseItem(squat), exerciseItem(bench), exerciseItem(row)]
        )

        let upNext = SessionStagePresentation.upNextItem(after: items.first, in: items)

        #expect(upNext?.id == "exercise-2")
    }

    @Test func upNextWrapsAroundToEarlierIncompleteItems() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.logged])
        let row = makeExercise(name: "DB Row", order: 2, setStates: [.pending])
        let items = SessionStagePresentation.items(
            [exerciseItem(squat), exerciseItem(bench), exerciseItem(row)]
        )

        let upNext = SessionStagePresentation.upNextItem(after: items.last, in: items)

        #expect(upNext?.id == "exercise-0")
    }

    @Test func upNextIsNilWhenNoOtherItemRemains() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let items = SessionStagePresentation.items([exerciseItem(squat), exerciseItem(bench)])

        #expect(SessionStagePresentation.upNextItem(after: items.last, in: items) == nil)
        #expect(SessionStagePresentation.upNextItem(after: nil, in: items) == nil)
    }

    @Test func completedSetCountCountsSettledSetsAcrossSupersetExercises() throws {
        let press = makeExercise(name: "Press", order: 1, setStates: [.logged, .pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.skipped, .pending])
        let item = SessionStagePresentation.items([try supersetItem(press, row)])[0]

        #expect(item.completedSetCount == 2)
    }

    @Test func stageItemWithZeroSetsIsNotComplete() {
        // Unified empty-set boundary: a stage holding no Sets reports not
        // complete, matching the model accessors — not the old vacuously-true
        // reading. Per the glossary an Exercise has ≥1 Set, so this only guards
        // the degenerate case.
        let empty = makeExercise(name: "Squat", order: 0, setStates: [])
        let item = SessionStagePresentation.items([exerciseItem(empty)])[0]

        #expect(!item.isComplete)
    }

    @Test func stageItemWithAllSettledSetsIsComplete() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .skipped])
        let item = SessionStagePresentation.items([exerciseItem(squat)])[0]

        #expect(item.isComplete)
    }

    @Test func queueProgressLabelCountsCompletedItems() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.skipped])
        let row = makeExercise(name: "DB Row", order: 2, setStates: [.pending])
        let items = SessionStagePresentation.items(
            [exerciseItem(squat), exerciseItem(bench), exerciseItem(row)]
        )

        #expect(SessionStagePresentation.queueProgressLabel(for: items) == "2 of 3")
    }

    @Test func completionSummaryCountsSupersetExercisesIndividually() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .logged])
        let press = makeExercise(name: "Press", order: 1, setStates: [.logged, .pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.skipped, .pending])
        let items = SessionStagePresentation.items(
            [exerciseItem(squat), try supersetItem(press, row)]
        )

        #expect(
            SessionStagePresentation.completionSummary(for: items)
                == "4 sets done across 3 exercises"
        )
    }

    @Test func completionSummaryUsesSingularForms() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let items = SessionStagePresentation.items([exerciseItem(squat)])

        #expect(SessionStagePresentation.completionSummary(for: items) == "1 set done across 1 exercise")
    }

    @Test func stageSetPrefersTheActiveSetOverTheFirstPending() throws {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending, .pending, .pending])
        let sortedSets = SessionStagePresentation.items([exerciseItem(squat)])[0].sortedSets

        let staged = SessionStagePresentation.stageSet(
            activeSetID: ActiveSetID(exerciseOrder: 0, setIndex: 2),
            in: sortedSets
        )

        #expect(staged?.index == 2)
    }

    @Test func stageSetFallsBackToTheFirstPendingSet() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .skipped, .pending])
        let sortedSets = SessionStagePresentation.items([exerciseItem(squat)])[0].sortedSets

        let staged = SessionStagePresentation.stageSet(activeSetID: nil, in: sortedSets)

        #expect(staged?.index == 2)
    }

    @Test func stageItemWalksBothSupersetExercisesInExerciseThenSetIndexOrder() throws {
        // A Superset render item flattens both Exercises' Sets in Exercise-order
        // then Set-index order, and its next-Pending reading skips the leading
        // Logged/Skipped Sets to the first Pending one (the third Press Set).
        let press = makeExercise(name: "Press", order: 1, setStates: [.logged, .skipped, .pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending, .logged])
        let item = SessionStagePresentation.items([try supersetItem(press, row)])[0]
        let pressPending = try #require(press.sets.first { $0.index == 2 })

        #expect(item.sortedSets.map(\.index) == [0, 1, 2, 0, 1])
        #expect(item.sortedSets.first === press.sets.first { $0.index == 0 })
        #expect(item.sortedSets.last === row.sets.first { $0.index == 1 })
        #expect(item.nextPendingSet === pressPending)
    }

    @Test func stageSetSkipsSettledSetsToTheFirstPendingSet() {
        // With a Logged/Skipped/Pending/Pending Exercise and no active Set, the
        // stage falls back to the first Pending Set — the third Set.
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .skipped, .pending, .pending])
        let item = SessionStagePresentation.items([exerciseItem(squat)])[0]

        let staged = SessionStagePresentation.stageSet(activeSetID: nil, in: item.sortedSets)

        #expect(staged === squat.sets.first { $0.index == 2 })
    }

    @Test func stageSetIsNilWhenNothingIsPending() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .skipped])
        let sortedSets = SessionStagePresentation.items([exerciseItem(squat)])[0].sortedSets

        #expect(SessionStagePresentation.stageSet(activeSetID: nil, in: sortedSets) == nil)
    }

    @Test func ordinalFollowsSupersetSetOrderAcrossBothExercises() throws {
        let press = makeExercise(name: "Press", order: 1, setStates: [.pending, .pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending])
        let item = SessionStagePresentation.items([try supersetItem(press, row)])[0]
        let sortedSets = item.sortedSets
        let firstRowSet = try #require(row.sets.first)

        #expect(sortedSets.count == 3)
        #expect(SessionStagePresentation.ordinal(of: firstRowSet, in: sortedSets) == 3)
    }

    @Test func supersetItemContainsSetsFromBothExercisesAndJoinsTitles() throws {
        let press = makeExercise(name: "Press", order: 1, setStates: [.pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending])
        let item = SessionStagePresentation.items([try supersetItem(press, row)])[0]

        #expect(item.contains(ActiveSetID(exerciseOrder: 2, setIndex: 0)))
        #expect(!item.contains(ActiveSetID(exerciseOrder: 0, setIndex: 0)))
        #expect(item.title == "Press + Row")
    }

    @Test func pairingRoleIsNoneWhileInactive() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let items = SessionStagePresentation.items(
            [exerciseItem(squat, pairingAvailability: .available)]
        )

        #expect(SessionStagePresentation.pairingRole(of: items[0], mode: .inactive) == QueuePairingRole.none)
    }

    @Test func pairingRoleMarksSourceEligibleAndIneligibleWhileSelecting() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let carry = makeExercise(name: "Farmer Carry", order: 2, setStates: [.pending])
        let items = SessionStagePresentation.items([
            exerciseItem(squat, pairingAvailability: .available),
            exerciseItem(bench, pairingAvailability: .available),
            exerciseItem(carry, pairingAvailability: .unavailable),
        ])
        let mode = PairingMode.selecting(sourceOrder: 0)

        #expect(SessionStagePresentation.pairingRole(of: items[0], mode: mode) == .source)
        #expect(SessionStagePresentation.pairingRole(of: items[1], mode: mode) == .eligibleTarget)
        #expect(SessionStagePresentation.pairingRole(of: items[2], mode: mode) == .ineligibleTarget)
    }

    @Test func pairingRoleMarksTheConfirmingTarget() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])
        let items = SessionStagePresentation.items([
            exerciseItem(squat, pairingAvailability: .available),
            exerciseItem(bench, pairingAvailability: .available),
        ])
        let mode = PairingMode.confirming(sourceOrder: 0, targetOrder: 1)

        #expect(SessionStagePresentation.pairingRole(of: items[0], mode: mode) == .source)
        #expect(SessionStagePresentation.pairingRole(of: items[1], mode: mode) == .confirmingTarget)
    }

    @Test func branchNodeStatesInkOneLeafPerLoggedSetAndDashLeafPerSkip() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .skipped, .pending, .pending])
        let sets = SessionStagePresentation.items([exerciseItem(squat)])[0].sortedSets

        let states = SessionStagePresentation.branchNodeStates(for: sets, activeSetID: nil)

        // Logged → leaf, Skipped → dashed leaf, the first Pending buds, the rest stay futures.
        #expect(states == [.leaf, .dashedLeaf, .bud, .future])
    }

    @Test func branchNodeStatesBudRidesTheActiveSet() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.pending, .pending, .pending])
        let sets = SessionStagePresentation.items([exerciseItem(squat)])[0].sortedSets

        let states = SessionStagePresentation.branchNodeStates(
            for: sets,
            activeSetID: ActiveSetID(exerciseOrder: 0, setIndex: 2)
        )

        // The bud follows focus onto the third Set; the earlier Pending Sets stay futures.
        #expect(states == [.future, .future, .bud])
    }

    @Test func branchNodeStatesAreAllLeavesWhenEverySetIsLogged() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged, .logged])
        let sets = SessionStagePresentation.items([exerciseItem(squat)])[0].sortedSets

        #expect(SessionStagePresentation.branchNodeStates(for: sets, activeSetID: nil) == [.leaf, .leaf])
    }

    @Test func supersetPartnerBranchNeverCarriesTheBud() {
        // The bud rides the focus (DESIGN.md §5.4): the partner's next Pending
        // Set reads as a future stroke, not a waking bud — only the focused
        // branch buds.
        let partner = makeExercise(name: "Row", order: 2, setStates: [.logged, .skipped, .pending, .pending])
        let sets = partner.sets.sorted { $0.index < $1.index }

        let states = SessionStagePresentation.supersetPartnerNodeStates(for: sets)

        #expect(states == [.leaf, .dashedLeaf, .future, .future])
    }

    @Test func supersetForkPutsTheBudOnTheFocusAndSubordinatesThePartner() {
        // The focused Exercise's branch carries the leaves and the one open bud
        // at full stroke; the partner is a bud-less lateral. The name line is the
        // Fraunces "& partner" (DESIGN.md §5.4).
        let focused = makeExercise(name: "DB Incline Press", order: 1, setStates: [.logged, .pending, .pending])
        let partner = makeExercise(name: "Chest-Supported Row", order: 2, setStates: [.pending, .pending])

        let fork = SessionStagePresentation.supersetFork(
            focused: focused,
            partner: partner,
            activeSetID: ActiveSetID(exerciseOrder: 1, setIndex: 1)
        )

        #expect(fork.focusedNodes == [.leaf, .bud, .future])
        #expect(fork.partnerNodes == [.future, .future])
        #expect(fork.partnerNameLine == "& Chest-Supported Row")
        #expect(fork.partnerExerciseOrder == 2)
    }

    @Test func pairingRoleTreatsSupersetItemsAsIneligibleTargets() throws {
        let press = makeExercise(name: "Press", order: 1, setStates: [.pending])
        let row = makeExercise(name: "Row", order: 2, setStates: [.pending])
        let items = SessionStagePresentation.items([try supersetItem(press, row)])

        #expect(
            SessionStagePresentation.pairingRole(of: items[0], mode: .selecting(sourceOrder: 0))
                == .ineligibleTarget
        )
    }
}

// MARK: - Quadratic bezier (the shared stem/branch geometry)

@Test func quadraticBezierAnchorsAtItsEndpoints() {
    let curve = QuadraticBezier(
        start: CGPoint(x: 10, y: 90),
        control: CGPoint(x: 55, y: 20),
        end: CGPoint(x: 100, y: 40)
    )

    #expect(curve.point(at: 0) == curve.start)
    #expect(curve.point(at: 1) == curve.end)
}

@Test func quadraticBezierPointMatchesTheClosedForm() {
    let curve = QuadraticBezier(
        start: CGPoint(x: 10, y: 90),
        control: CGPoint(x: 55, y: 20),
        end: CGPoint(x: 100, y: 40)
    )

    // An independent re-derivation of the formula the views used inline before the extraction,
    // proving the shared helper is byte-identical (the visual baselines depend on it).
    for t in stride(from: 0.0 as CGFloat, through: 1.0, by: 0.1) {
        let mt = 1 - t
        let expected = CGPoint(
            x: mt * mt * curve.start.x + 2 * mt * t * curve.control.x + t * t * curve.end.x,
            y: mt * mt * curve.start.y + 2 * mt * t * curve.control.y + t * t * curve.end.y
        )
        #expect(curve.point(at: t) == expected)
    }
}

@Test func quadraticBezierTangentMatchesTheClosedFormAndPointsFromStartToEnd() {
    let curve = QuadraticBezier(
        start: CGPoint(x: 10, y: 90),
        control: CGPoint(x: 55, y: 20),
        end: CGPoint(x: 100, y: 40)
    )

    for t in stride(from: 0.0 as CGFloat, through: 1.0, by: 0.25) {
        let mt = 1 - t
        let expected = CGVector(
            dx: 2 * mt * (curve.control.x - curve.start.x) + 2 * t * (curve.end.x - curve.control.x),
            dy: 2 * mt * (curve.control.y - curve.start.y) + 2 * t * (curve.end.y - curve.control.y)
        )
        #expect(curve.tangent(at: t) == expected)
    }

    // This stem climbs left→right, so every tangent advances in +x (leaves never point backwards).
    #expect(curve.tangent(at: 0).dx > 0)
    #expect(curve.tangent(at: 1).dx > 0)
}

// MARK: - Branch node layout (terminal-anchored spacing along the stem)

@Test func branchNodeLayoutSpreadsManyNodesAcrossTheFullSpan() {
    // Five nodes over 0.16…0.80: the natural step (0.16) is under the cap, so
    // the ends pin to the span — larger counts spread exactly as before.
    let ts = (0..<5).map {
        BranchNodeLayout.nodeT(index: $0, count: 5, first: 0.16, last: 0.80, maxStep: 0.24)
    }

    #expect(abs(ts[0] - 0.16) < 0.0001)
    #expect(abs(ts[4] - 0.80) < 0.0001)
}

@Test func branchNodeLayoutAnchorsTwoNodesToTheTerminal() {
    // Two Sets: the uncapped step would pin them to opposite ends of the branch
    // — too far apart to read as one sprig. The verdict anchors the last node
    // to the terminal and steps the other down by the capped step.
    let first = BranchNodeLayout.nodeT(index: 0, count: 2, first: 0.16, last: 0.80, maxStep: 0.24)
    let second = BranchNodeLayout.nodeT(index: 1, count: 2, first: 0.16, last: 0.80, maxStep: 0.24)

    #expect(abs(second - 0.80) < 0.0001)
    #expect(abs(first - 0.56) < 0.0001)
}

@Test func branchNodeLayoutThreeNodesStepDownFromTheTerminal() {
    let ts = (0..<3).map {
        BranchNodeLayout.nodeT(index: $0, count: 3, first: 0.16, last: 0.80, maxStep: 0.24)
    }

    #expect(abs(ts[2] - 0.80) < 0.0001)
    #expect(abs(ts[1] - 0.56) < 0.0001)
    #expect(abs(ts[0] - 0.32) < 0.0001)
}

@Test func branchNodeLayoutPutsASingleNodeAtTheTerminal() {
    let t = BranchNodeLayout.nodeT(index: 0, count: 1, first: 0.16, last: 0.80, maxStep: 0.24)

    #expect(abs(t - 0.80) < 0.0001)
}
