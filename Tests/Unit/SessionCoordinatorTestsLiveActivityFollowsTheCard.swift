import Foundation
import Testing

@testable import WorkoutTracker

/// A log brings the Lock Screen card up on the Set the stage moved to, in one start. A second
/// send in the same turn replaces the start, and a retarget brings up no activity of its own, so
/// the card it named would never reach the Lock Screen.
@MainActor
struct LiveActivityFollowsTheCardTests {
    enum Path: String, CaseIterable, CustomTestStringConvertible {
        case inOrder
        case pickedOutOfOrder
        case withinASuperset
        case leavingASuperset
        case pickedOutsideASuperset

        var testDescription: String { rawValue }
    }

    @MainActor
    private struct Stage {
        let session: Session
        let coordinator: SessionCoordinator
        let liveActivity: SpySessionLiveActivityAdapter
        let pullUps: Exercise
        let bench: Exercise
        let row: Exercise

        init() throws {
            let session = Session(dayNumber: 1, date: nil)
            session.exercises = [
                Self.exercise("Pull Ups", order: 0),
                Self.exercise("Flat DB BP", order: 1),
                Self.exercise("DB Row", order: 2)
            ]
            self.session = placedInBlock(session, blockTab: "Block 31")
            connectCoordinatorWeek([session])
            liveActivity = SpySessionLiveActivityAdapter()
            coordinator = SessionCoordinator(
                session: session,
                wiring: .fixture(
                    logging: SpySessionLoggingAdapter(),
                    navigation: SpySessionNavigationAdapter(current: session),
                    sync: SpySessionSyncAdapter(),
                    restTimer: RestTimer(clock: ManualCoordinatorRestClock(now: Date(timeIntervalSinceReferenceDate: 2_000))),
                    restDurations: restDurations(standard: 120),
                    liveActivity: liveActivity,
                    motion: ImmediateSessionMotion()
                )
            )
            pullUps = try #require(session.exercises.first { $0.order == 0 })
            bench = try #require(session.exercises.first { $0.order == 1 })
            row = try #require(session.exercises.first { $0.order == 2 })
        }

        private static func exercise(_ name: ExerciseName, order: Int) -> Exercise {
            let exercise = Exercise(name: name, coachNote: nil, order: order)
            exercise.sets = (0..<2).map {
                ExerciseSet(index: $0, prescribedReps: "10", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
            }
            return exercise
        }

        func log(_ set: ExerciseSet) {
            coordinator.log(set, as: SetLog(weight: .pounds(90), reps: 10, rpe: .ten))
        }

        func logTheCard() throws {
            log(try #require(coordinator.focusManager.activeSet(in: session)).set)
        }
    }

    @Test(arguments: Path.allCases)
    func aLogStartsTheCardOnTheSetTheStageMovedTo(_ path: Path) throws {
        let stage = try Stage()
        switch path {
        case .inOrder:
            try stage.logTheCard()
        case .pickedOutOfOrder:
            stage.coordinator.focus(on: try #require(stage.row.sets.first))
        case .withinASuperset, .leavingASuperset:
            #expect(stage.coordinator.createSuperset(from: stage.pullUps, to: stage.bench, in: stage.session))
            if path == .leavingASuperset {
                for _ in 0..<3 { try stage.logTheCard() }
            }
        case .pickedOutsideASuperset:
            #expect(stage.coordinator.createSuperset(from: stage.pullUps, to: stage.bench, in: stage.session))
            stage.coordinator.focus(on: try #require(stage.row.sets.first))
        }
        let before = (starts: stage.liveActivity.calls.count, retargets: stage.liveActivity.retargets.count)

        try stage.logTheCard()

        let card = try #require(stage.coordinator.focusManager.activeSet(in: stage.session))
        #expect(stage.liveActivity.calls.count == before.starts + 1)
        #expect(stage.liveActivity.retargets.count == before.retargets)
        let started = try #require(stage.liveActivity.calls.last?.content)
        #expect(started.target?.setID == card.setID)
        #expect(started.exerciseName == card.exercise.exerciseName.base)
    }
}
