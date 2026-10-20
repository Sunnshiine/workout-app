import Foundation
import Observation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func sessionCoordinatorContainer() throws -> ModelContainer {
    try ModelContainer(
        for: LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "session-coordinator-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@MainActor
@Test func coordinatorBindExposesInitialFocusThroughCoordinatorInterface() {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func theStageListsOrdinaryExercisesInSessionOrderWithTheirPairingRoles() throws {
    let session = makeCoordinatorSession()
    let clock = ManualSessionTransitionClock()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture(), transitionClock: clock)
    let firstBenchSet = try #require(session.exercises.first { $0.order == 1 }?.sets.first { $0.index == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })

    firstBenchSet.state = .logged
    coordinator.advanceAfterLog(firstBenchSet, in: session)
    #expect(coordinator.beginPairing(from: bench, in: session))
    let selecting = coordinator.stage(in: session, lookup: .empty).queue
    #expect(selecting.pairingMode == .selecting(sourceOrder: 1))
    #expect(selecting.rows.map(\.pairingRole) == [.ineligibleTarget, .source, .eligibleTarget])
    #expect(selecting.rows.map(\.kind) == [.exercise, .pairableExercise, .pairableExercise])
    #expect(coordinator.handlePairingTap(on: row, in: session) == .confirming)

    let stage = coordinator.stage(in: session, lookup: .empty)

    #expect(stage.queue.rows.map(\.id) == ["exercise-0", "exercise-1", "exercise-2"])
    #expect(stage.queue.rows.map(\.isOnStage) == [false, true, false])
    #expect(exerciseStage(coordinator, in: session)?.branch.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
    #expect(stage.queue.rows.map(\.pairingRole) == [.ineligibleTarget, .source, .confirmingTarget])
}

@MainActor
@Test func coordinatorExpandsLoggedSetReviewWithoutChangingActivePendingSet() throws {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let completedSquatSet = try #require(session.exercises.first { $0.order == 0 }?.sets.first)

    coordinator.focus(on: completedSquatSet)

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(coordinator.expandedLoggedSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))

    let review = try #require(exerciseStage(coordinator, in: session))
    #expect(review.exercise === completedSquatSet.exercise)
    #expect(review.branch.activeSetID == nil)
    #expect(review.card?.cardIdentity == "stage-review-0-0")

    coordinator.focus(on: completedSquatSet)

    #expect(coordinator.expandedLoggedSetID == nil)
    let active = try #require(exerciseStage(coordinator, in: session))
    #expect(active.branch.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(active.card?.cardIdentity == "stage-active-1-0")
}

@MainActor
@Test func theStageFusesASupersetAtItsLowerOrderedSideInSessionOrder() throws {
    let session = makeFourExercisePairingSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let press = try #require(session.exercises.first { $0.order == 0 })
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let row = try #require(session.exercises.first { $0.order == 3 })

    #expect(coordinator.createSuperset(from: squat, to: row, in: session))

    let rows = coordinator.stage(in: session, lookup: .empty).queue.rows

    #expect(rows.map(\.id) == ["exercise-0", "superset-1", "exercise-2"])
    #expect(rows.map(\.title) == ["Press", "Squat + DB Row", "Bench Press"])
    #expect(rows.map(\.pairingExercise) == [press, squat, bench])
    #expect(rows[1].sets == squat.sets + row.sets)
}

@MainActor
@Test func theStageCarriesTheLastPerformedLineFromTheLookupStore() throws {
    let container = try sessionCoordinatorContainer()
    let context = container.mainContext
    context.insert(
        LastPerformedEntry(
            exerciseName: "Bench Press",
            resultText: "185x6@7",
            performedOn: Date(timeIntervalSinceReferenceDate: 100),
            source: "W3 D2"
        )
    )
    try context.save()
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())

    let stage = coordinator.stage(in: session, lookup: LastPerformedLookupStore(context: context).snapshot)

    guard case .exercise(let bench) = stage.focus else {
        Issue.record("Expected Bench Press on stage")
        return
    }
    #expect(bench.exercise.order == 1)
    #expect(bench.lastPerformed?.resultText == "185x6@7")
    #expect(bench.lastPerformed?.sourceText == "W3 D2")
    withExtendedLifetime(container) {}
}

@MainActor
@Test func loggingSetUsesAdaptersAdvancesFocusAndFlushes() throws {
    let fixture = try makeActionFixture()
    let bench = try #require(fixture.session.exercises.first { $0.order == 1 })
    let firstBenchSet = try #require(bench.sets.first { $0.index == 0 })
    let log = SetLog(weight: .pounds(185), reps: 6, rpe: .seven)

    fixture.coordinator.log(firstBenchSet, as: log)

    #expect(fixture.logging.loggedSets.count == 1)
    #expect(fixture.logging.loggedSets.first?.set === firstBenchSet)
    #expect(fixture.logging.loggedSets.first?.log == log)
    #expect(fixture.coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 1))
    #expect(fixture.sync.flushRequestCount == 1)
    #expect(fixture.sync.reportedErrors.isEmpty)
}

@MainActor
@Test func theStageOffersMoveOnAndOpenExercisesOnlyAtTheLiveEdge() throws {
    let session = makeCoordinatorSession()
    let makeup = Exercise(name: "Front Squat", coachNote: nil, order: 0)
    let navigation = SpySessionNavigationAdapter()
    navigation.canMoveOn = true
    navigation.openExercises = [makeup]
    var isAtLiveEdge = true
    navigation.liveEdgeOfSession = { isAtLiveEdge ? .atLiveEdge(currentSession: $0) : .browsedAway }
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(
            logging: SpySessionLoggingAdapter(),
            navigation: navigation,
            sync: SpySessionSyncAdapter(),
            motion: ImmediateSessionMotion()
        )
    )

    let atLiveEdge = coordinator.stage(in: session, lookup: .empty).queue
    isAtLiveEdge = false
    let browsedAway = coordinator.stage(in: session, lookup: .empty).queue

    #expect(atLiveEdge.showsMoveOn)
    #expect(atLiveEdge.openExercises == [makeup])
    #expect(!browsedAway.showsMoveOn)
    #expect(browsedAway.openExercises.isEmpty)
}

@MainActor
@Test func aStageReadBeforeTheBindAlreadyOffersMoveOn() throws {
    let (session, set) = makeSingleSetSession(dayNumber: 1)
    set.state = .logged
    let navigation = SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) })
    navigation.canMoveOn = true
    let coordinator = SessionCoordinator(wiring: .fixture(navigation: navigation))

    #expect(coordinator.stage(in: session, lookup: .empty).queue.showsMoveOn)
}

@MainActor
@Test func rebindingToTheSameSessionLeavesAStageReadAlone() throws {
    let (session, set) = makeSingleSetSession(dayNumber: 1)
    set.state = .logged
    let navigation = SpySessionNavigationAdapter(liveEdge: { .atLiveEdge(currentSession: $0) })
    navigation.canMoveOn = true
    let coordinator = SessionCoordinator(session: session, wiring: .fixture(navigation: navigation))
    let rebind = ObservedChanges()
    rebind.watch { _ = coordinator.stage(in: session, lookup: .empty) }

    coordinator.view(session)

    #expect(rebind.fired == 0)
    #expect(coordinator.stage(in: session, lookup: .empty).queue.showsMoveOn)
}

@MainActor
@Test func readingTheStageWritesNoObservedState() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))
    for set in squat.sets {
        set.state = .logged
    }
    let changes = ObservedChanges()
    changes.watch { _ = coordinator.stage(in: session, lookup: .empty) }

    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2"])

    #expect(changes.fired == 0)
}
