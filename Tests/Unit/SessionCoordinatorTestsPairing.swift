import Foundation
import Observation
import SwiftData
import Testing

@testable import WorkoutTracker

private func makeIntegratedCoordinatorSession() -> Session {
    let session = Session(dayNumber: 1, date: nil)

    let squat = Exercise(name: "Squat", coachNote: nil, order: 0)
    let firstSquatSet = ExerciseSet(
        index: 0,
        prescribedReps: "5",
        prescribedLoad: "RPE 7",
        percentOneRM: nil,
        state: .pending
    )
    let secondSquatSet = ExerciseSet(
        index: 1,
        prescribedReps: "5",
        prescribedLoad: "RPE 8",
        percentOneRM: nil,
        state: .pending
    )
    squat.sets = [firstSquatSet, secondSquatSet]

    let bench = Exercise(name: "Bench Press", coachNote: nil, order: 1)
    bench.sets = [
        ExerciseSet(index: 0, prescribedReps: "6", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let row = Exercise(name: "DB Row", coachNote: nil, order: 2)
    row.sets = [
        ExerciseSet(index: 0, prescribedReps: "10", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    let pulldown = Exercise(name: "Lat Pulldown", coachNote: nil, order: 3)
    pulldown.sets = [
        ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    ]

    session.exercises = [pulldown, row, bench, squat]
    return placedInBlock(session)
}

@MainActor
private func supersetStage(_ coordinator: SessionCoordinator, in session: Session) -> SupersetStage? {
    guard case .superset(let stage) = coordinator.stage(in: session, lookup: .empty).focus else { return nil }
    return stage
}

@MainActor
@Test func coordinatorBeginsPairingOnlyFromEligibleExercise() throws {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let completedSquat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })

    #expect(!coordinator.beginPairing(from: completedSquat, in: session))
    #expect(coordinator.pairingMode == .inactive)

    #expect(coordinator.beginPairing(from: bench, in: session))
    #expect(coordinator.pairingMode == .selecting(sourceOrder: 1))
}

@MainActor
@Test func coordinatorHandlesSourceAndUnavailablePairingTaps() throws {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let completedSquat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })

    #expect(coordinator.beginPairing(from: bench, in: session))
    #expect(coordinator.handlePairingTap(on: completedSquat, in: session) == .unavailable)
    #expect(coordinator.pairingMode == .selecting(sourceOrder: 1))

    #expect(coordinator.handlePairingTap(on: bench, in: session) == .cancelled)
    #expect(coordinator.pairingMode == .inactive)
}

@MainActor
@Test func coordinatorSourceTapCancelsPairingConfirmation() throws {
    let session = makeCoordinatorSession()
    let clock = ManualSessionTransitionClock()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture(), transitionClock: clock)
    let completedSquat = try #require(session.exercises.first { $0.order == 0 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })

    #expect(coordinator.beginPairing(from: bench, in: session))
    #expect(coordinator.handlePairingTap(on: row, in: session) == .confirming)
    #expect(coordinator.handlePairingTap(on: completedSquat, in: session) == .unavailable)
    #expect(coordinator.pairingMode == .confirming(sourceOrder: 1, targetOrder: 2))

    #expect(coordinator.handlePairingTap(on: bench, in: session) == .cancelled)
    #expect(coordinator.pairingMode == .inactive)
    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2"])
}

@MainActor
@Test func coordinatorCreatesSupersetAfterClockControlledPairingConfirmation() async throws {
    let session = makePlannedPairingSession()
    let clock = ManualSessionTransitionClock()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture(), transitionClock: clock)
    let initialActiveSetID = coordinator.activeSetID
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })

    #expect(coordinator.beginPairing(from: squat, in: session))
    #expect(coordinator.handlePairingTap(on: bench, in: session) == .confirming)
    #expect(coordinator.pairingMode == .confirming(sourceOrder: 1, targetOrder: 2))
    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2"])

    await clock.waitForSleep()

    #expect(clock.sleptDurations == [.milliseconds(220)])
    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2"])

    await clock.advance()

    #expect(coordinator.pairingMode == .inactive)
    #expect(coordinator.activeSetID == initialActiveSetID)
    let rows = coordinator.stage(in: session, lookup: .empty).queue.rows
    #expect(rows.map(\.id) == ["exercise-0", "superset-1"])
    #expect(rows.map(\.title) == ["Press", "Squat + Bench Press"])
}

@MainActor
@Test func coordinatorDismissesSupersetClearsPairingModeAndReconcilesFocus() throws {
    let session = makeFourExercisePairingSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let press = try #require(session.exercises.first { $0.order == 0 })
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })

    #expect(coordinator.createSuperset(from: press, to: squat, in: session))
    #expect(coordinator.beginPairing(from: bench, in: session))

    coordinator.dismissSuperset(containing: press, in: session)

    #expect(coordinator.pairingMode == .inactive)
    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2", "exercise-3"])
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
}

@MainActor
@Test func unlinkingTheSupersetFromItsQueueRowKeepsTheFocusedSideOnStage() throws {
    let session = makeFourExercisePairingSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let press = try #require(session.exercises.first { $0.order == 0 })
    let squat = try #require(session.exercises.first { $0.order == 1 })

    #expect(coordinator.createSuperset(from: press, to: squat, in: session))
    #expect(coordinator.focusNextSupersetSet(for: squat, in: session))
    #expect(supersetStage(coordinator, in: session)?.focused === squat)
    let supersetRow = try #require(coordinator.stage(in: session, lookup: .empty).queue.rows.first)
    #expect(supersetRow.kind == .superset)

    coordinator.dismissSuperset(containing: supersetRow.pairingExercise, in: session)

    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2", "exercise-3"])
    #expect(exerciseStage(coordinator, in: session)?.exercise.order == 1)
}

@MainActor
@Test func coordinatorFocusesPairedExerciseNextPendingSet() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })

    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))
    #expect(coordinator.focusNextSupersetSet(for: bench, in: session))

    let expectedSetID = ActiveSetID(exerciseOrder: 2, setIndex: 0)
    #expect(coordinator.activeSetID == expectedSetID)
}

@MainActor
@Test func coordinatorMembershipAgreesForPlannedButNotYetActiveSuperset() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let press = try #require(session.exercises.first { $0.order == 0 })
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })

    // Focus stays on the unpaired press; the Superset is planned but not yet active.
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))

    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "superset-1"])
    #expect(exerciseStage(coordinator, in: session)?.exercise === press)

    // The domain-predicate membership answers must agree with that projection while the
    // Superset is planned but not yet active: the unpaired press is not a member, so it
    // resolves no focus target …
    #expect(!coordinator.focusNextSupersetSet(for: press, in: session))
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))

    // … while a paired side is a member and resolves its next Pending Set as the target.
    #expect(coordinator.focusNextSupersetSet(for: bench, in: session))
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
}

@MainActor
@Test func aSupersetLogKeepsThePairOnStageBeforeDuringAndAfterTheFocusMove() throws {
    let session = makeSquatAndRDLSession()
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let rdl = try #require(session.exercises.first { $0.order == 1 })
    let logging = SpySessionLoggingAdapter()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture(logging: logging, sync: SpySessionSyncAdapter()))
    #expect(coordinator.createSuperset(from: squat, to: rdl, in: session))
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    #expect(supersetStage(coordinator, in: session)?.card?.cardIdentity == "superset-active-0-0")
    var focusInsideTheLog: ActiveSetID?
    var cardInsideTheLog: String?
    logging.afterLogWrite = {
        focusInsideTheLog = coordinator.activeSetID
        cardInsideTheLog = supersetStage(coordinator, in: session)?.card?.cardIdentity
    }

    coordinator.log(firstSquatSet, as: SetLog(weight: .pounds(225), reps: 5, rpe: .seven))

    #expect(focusInsideTheLog == ActiveSetID(exerciseOrder: 0, setIndex: 0))
    #expect(cardInsideTheLog == "superset-active-0-0")
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
    #expect(supersetStage(coordinator, in: session)?.card?.cardIdentity == "superset-active-1-0")
    #expect(stageRowIDs(coordinator, in: session) == ["superset-0"])
}

@MainActor
@Test func coordinatorPreservesCurrentSessionFlowThroughTheStage() throws {
    let session = makeIntegratedCoordinatorSession()
    let logging = SpySessionLoggingAdapter()
    let sync = SpySessionSyncAdapter()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture(logging: logging, sync: sync))
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let finalSquatSet = try #require(squat.sets.first { $0.index == 1 })
    let bench = try #require(session.exercises.first { $0.order == 1 })
    let row = try #require(session.exercises.first { $0.order == 2 })
    let squatLog = SetLog(weight: .pounds(315), reps: 5, rpe: .seven)

    coordinator.log(firstSquatSet, as: squatLog)

    #expect(firstSquatSet.state == .logged)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
    #expect(sync.flushRequestCount == 1)

    coordinator.deleteLog(for: firstSquatSet)

    #expect(firstSquatSet.state == .pending)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 0))

    coordinator.log(firstSquatSet, as: squatLog)
    coordinator.skip(finalSquatSet)

    #expect(finalSquatSet.state == .skipped)
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))

    #expect(coordinator.createSuperset(from: bench, to: row, in: session))

    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "superset-1", "exercise-3"])
    #expect(supersetStage(coordinator, in: session)?.branch.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))

    #expect(coordinator.focusNextSupersetSet(for: row, in: session))
    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(supersetStage(coordinator, in: session)?.focused === row)

    coordinator.dismissSuperset(containing: row, in: session)

    #expect(stageRowIDs(coordinator, in: session) == ["exercise-0", "exercise-1", "exercise-2", "exercise-3"])
    #expect(logging.loggedSets.map(\.set) == [firstSquatSet, firstSquatSet])
    #expect(logging.skippedSets == [finalSquatSet])
    #expect(logging.deletedSets == [firstSquatSet])
    #expect(sync.reportedErrors.isEmpty)
}

@MainActor
@Test func showingAnOpenExercisesSessionCancelsPairingAndShowsItsAddress() throws {
    let session = makeCoordinatorSession()
    let earlier = Session(dayNumber: 1, date: nil)
    let makeup = Exercise(name: "Front Squat", coachNote: nil, order: 0)
    earlier.exercises = [makeup]
    connectCoordinatorWeek([earlier, session])
    let navigation = SpySessionNavigationAdapter()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture(navigation: navigation))
    let bench = try #require(session.exercises.first { $0.order == 1 })
    #expect(coordinator.beginPairing(from: bench, in: session))

    coordinator.showSourceSession(of: makeup)

    #expect(coordinator.pairingMode == .inactive)
    #expect(navigation.shownAddresses == [SessionAddress(week: 1, day: 1)])
}

@MainActor
@Test func aSupersetEndedByLoggingOneSidesLastSetStaysEndedWhenThatLogIsDeleted() throws {
    let session = makePlannedPairingSession()
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(logging: SpySessionLoggingAdapter(), sync: SpySessionSyncAdapter())
    )
    let squat = try #require(session.exercises.first { $0.order == 1 })
    let bench = try #require(session.exercises.first { $0.order == 2 })
    let lastSquatSet = try #require(squat.sets.first)
    #expect(coordinator.createSuperset(from: squat, to: bench, in: session))

    coordinator.log(lastSquatSet, as: SetLog(weight: .pounds(315), reps: 5, rpe: .seven))
    coordinator.deleteLog(for: lastSquatSet)

    #expect(lastSquatSet.state == .pending)
    let rows = coordinator.stage(in: session, lookup: .empty).queue.rows
    #expect(rows.map(\.id) == ["exercise-0", "exercise-1", "exercise-2"])
    #expect(rows.map(\.kind) == [.pairableExercise, .pairableExercise, .pairableExercise])
}

@MainActor
@Test func rebindingAfterASupersetLogKeepsTheFocusOnThePartner() throws {
    let session = makeSquatAndRDLSession()
    let press = Exercise(name: "Press", coachNote: nil, order: 2)
    press.sets = [ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)]
    session.exercises.append(press)
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let rdl = try #require(session.exercises.first { $0.order == 1 })
    let firstSquatSet = try #require(squat.sets.first { $0.index == 0 })
    let pressSet = try #require(press.sets.first)
    let coordinator = SessionCoordinator(
        session: session,
        wiring: .fixture(logging: SpySessionLoggingAdapter(), sync: SpySessionSyncAdapter())
    )
    coordinator.focus(on: pressSet)
    #expect(coordinator.createSuperset(from: squat, to: rdl, in: session))
    coordinator.log(firstSquatSet, as: SetLog(weight: .pounds(225), reps: 5, rpe: .seven))

    coordinator.view(session)

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}
