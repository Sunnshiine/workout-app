#if DEBUG
    import Foundation
    import SwiftData

    enum WorkoutFixtureScenarios {
        static let sheetId = "FIXTURE"
        static let replacementSheetId = "REPLACEMENT"
        static let sheetURL = "https://docs.google.com/spreadsheets/d/\(sheetId)/edit"
        static let blockTab = "Block 27"

        @MainActor
        static func currentSessionWithPendingSetsBlock() -> Block {
            WorkoutFixtureBlocks.currentSessionWithPendingSetsBlock()
        }

        @MainActor
        static func partiallyLoggedSessionBlock() -> Block {
            WorkoutFixtureBlocks.partiallyLoggedSessionBlock()
        }

        @MainActor
        static func openExercisesBlock() -> Block {
            WorkoutFixtureBlocks.openExercisesBlock()
        }

        @MainActor
        static func blockOverviewWithMixedSessionStatesBlock() -> Block {
            WorkoutFixtureBlocks.blockOverviewWithMixedSessionStatesBlock()
        }

        @MainActor
        static func partiallyUploadedBlock() -> Block {
            WorkoutFixtureBlocks.partiallyUploadedBlock()
        }

        @MainActor
        static func uiLaunchBlock() -> Block {
            WorkoutFixtureBlocks.uiLaunchBlock()
        }

        @MainActor
        static func longSessionBlock() -> Block {
            WorkoutFixtureBlocks.longSessionBlock()
        }

        static func syncFailureState() -> SyncCoordinator.State {
            .conflict(["Sheet write failed"])
        }

        static func queuedWrite() -> PendingWrite {
            PendingWrite(
                blockTab: blockTab,
                week: 1,
                day: 1,
                exerciseName: "Back Squat",
                setIndex: 0,
                column: .notes,
                operation: .upsert,
                valueToWrite: "185x5@8",
                expectedCurrentValue: ""
            )
        }

        static func lastPerformedBackSquat() -> LastPerformedEntry {
            LastPerformedEntry(
                fullName: "Back Squat",
                baseName: "Back Squat",
                result: SetLog(weight: .pounds(255), reps: 5, rpe: 7),
                performedOn: Date(timeIntervalSinceReferenceDate: 100),
                source: "Block 26 · W4 D3"
            )
        }
    }

    private enum WorkoutFixtureBlocks {
        typealias Factory = WorkoutFixtureFactory

        @MainActor
        static func currentSessionWithPendingSetsBlock() -> Block {
            Factory.block(
                weeks: [
                    Factory.week(
                        1,
                        sessions: [
                            Factory.session(
                                weekNumber: 1,
                                dayNumber: 1,
                                exercises: [Factory.backSquat(), Factory.rdl()]
                            )
                        ]
                    )
                ]
            )
        }

        @MainActor
        static func partiallyLoggedSessionBlock() -> Block {
            Factory.block(
                weeks: [
                    Factory.week(
                        1,
                        sessions: [
                            Factory.session(
                                weekNumber: 1,
                                dayNumber: 1,
                                exercises: [Factory.partiallyLoggedBackSquat()]
                            )
                        ]
                    )
                ]
            )
        }

        @MainActor
        static func openExercisesBlock() -> Block {
            Factory.block(
                weeks: [
                    Factory.week(
                        1,
                        sessions: [
                            openBackSquatSession(),
                            openBenchPressSession(),
                            currentDeadliftSession()
                        ]
                    )
                ]
            )
        }

        @MainActor
        static func blockOverviewWithMixedSessionStatesBlock() -> Block {
            Factory.block(
                weeks: [
                    Factory.week(
                        1,
                        sessions: [
                            completeOverviewSession(),
                            hasOpenOverviewSession(),
                            currentOverviewSession()
                        ]
                    ),
                    Factory.week(2, sessions: [upcomingOverviewSession()])
                ]
            )
        }

        @MainActor
        static func partiallyUploadedBlock() -> Block {
            Factory.block(
                weeks: (1...4).map { weekNumber in
                    Factory.week(
                        weekNumber,
                        sessions: (1...4).map { dayNumber in
                            partialUploadSession(weekNumber: weekNumber, dayNumber: dayNumber)
                        }
                    )
                }
            )
        }

        @MainActor
        static func uiLaunchBlock() -> Block {
            Factory.block(
                weeks: (1...4).map { weekNumber in
                    Factory.week(
                        weekNumber,
                        sessions: (1...4).map { dayNumber in
                            uiLaunchSession(weekNumber: weekNumber, dayNumber: dayNumber)
                        }
                    )
                }
            )
        }

        @MainActor
        static func longSessionBlock() -> Block {
            Factory.block(
                weeks: [
                    Factory.week(
                        1,
                        sessions: [
                            Factory.session(
                                weekNumber: 1,
                                dayNumber: 1,
                                exercises: longSessionExercises()
                            )
                        ]
                    )
                ]
            )
        }

        private static func longSessionExercises() -> [Exercise] {
            [
                Factory.exercise(
                    name: "Primer Row",
                    baseName: "Primer Row",
                    coachNote: "Move crisply.",
                    order: 0,
                    sets: [Factory.loggedSet(0, reps: "8", load: "RPE6", weight: 95, rpe: 6)]
                ),
                longSessionExercise("Back Squat", order: 1, reps: "5", load: "RPE6", note: "Brace hard."),
                longSessionExercise("Bench Press", order: 2, reps: "5", load: "RPE6", note: "Pause every rep."),
                longSessionExercise("Chest-Supported Row", order: 3, reps: "10", load: "RPE7", note: "Pause at the top."),
                longSessionExercise("Split Squat", order: 4, reps: "8", load: "RPE7", note: "Keep the front foot planted."),
                longSessionExercise("Hamstring Curl", order: 5, reps: "12", load: "RPE8", note: "Control the eccentric."),
                longSessionExercise("Cable Crunch", order: 6, reps: "12", load: "RPE8", note: "Exhale hard."),
                longSessionExercise("Farmer Carry", order: 7, reps: "40 sec", load: "RPE7", note: "Tall posture.")
            ]
        }

        private static func longSessionExercise(
            _ name: String,
            order: Int,
            reps: String,
            load: String,
            note: String
        ) -> Exercise {
            Factory.exercise(
                name: name,
                baseName: name,
                coachNote: note,
                order: order,
                sets: [Factory.set(0, reps: reps, load: load)]
            )
        }

        private static func uiLaunchSession(weekNumber: Int, dayNumber: Int) -> Session {
            let exercises: [Exercise] =
                switch (weekNumber, dayNumber) {
                case (1, 1):
                    [Factory.backSquat(), Factory.rdl()]
                case (1, 2):
                    [Factory.benchPress(), Factory.pullUp()]
                case (1, 3):
                    [Factory.deadlift()]
                default:
                    [Factory.accessory(weekNumber: weekNumber, dayNumber: dayNumber)]
                }
            return Factory.session(weekNumber: weekNumber, dayNumber: dayNumber, exercises: exercises)
        }

        private static func partialUploadSession(weekNumber: Int, dayNumber: Int) -> Session {
            let exercises: [Exercise] =
                switch (weekNumber, dayNumber) {
                case (1, 1):
                    [Factory.backSquat(), Factory.rdl()]
                case (1, 2):
                    [Factory.benchPress(), Factory.pullUp()]
                case (2, 1):
                    [Factory.deadlift()]
                case (3, 1), (4, 1):
                    [Factory.accessory(weekNumber: weekNumber, dayNumber: dayNumber)]
                default:
                    []
                }
            return Factory.session(weekNumber: weekNumber, dayNumber: dayNumber, exercises: exercises)
        }

        private static func openBackSquatSession() -> Session {
            Factory.session(
                weekNumber: 1,
                dayNumber: 1,
                exercises: [Factory.partiallyLoggedBackSquat()]
            )
        }

        private static func openBenchPressSession() -> Session {
            Factory.session(
                weekNumber: 1,
                dayNumber: 2,
                exercises: [Factory.partiallyLoggedBenchPress()]
            )
        }

        private static func currentDeadliftSession() -> Session {
            Factory.session(
                weekNumber: 1,
                dayNumber: 3,
                exercises: [Factory.partiallyLoggedDeadlift()]
            )
        }

        private static func completeOverviewSession() -> Session {
            Factory.session(
                weekNumber: 1,
                dayNumber: 1,
                exercises: [
                    Factory.exercise(
                        name: "Competition Squat",
                        baseName: "Competition Squat",
                        coachNote: "Completed Session.",
                        order: 0,
                        sets: [
                            Factory.loggedSet(0, reps: "5", load: "RPE7", weight: 185, rpe: 7),
                            Factory.set(1, reps: "5", load: "RPE8", state: .skipped)
                        ]
                    )
                ]
            )
        }

        private static func hasOpenOverviewSession() -> Session {
            Factory.session(
                weekNumber: 1,
                dayNumber: 2,
                exercises: [
                    Factory.exercise(
                        name: "Paused Bench Press",
                        baseName: "Paused Bench Press",
                        coachNote: "Has Open Exercises.",
                        order: 0,
                        sets: [
                            Factory.loggedSet(0, reps: "5", load: "RPE7", weight: 155, rpe: 7),
                            Factory.set(1, reps: "5", load: "RPE8")
                        ]
                    )
                ]
            )
        }

        private static func currentOverviewSession() -> Session {
            Factory.session(
                weekNumber: 1,
                dayNumber: 3,
                exercises: [
                    Factory.exercise(
                        name: "Current Deadlift",
                        baseName: "Current Deadlift",
                        coachNote: "Current Session.",
                        order: 0,
                        sets: [
                            Factory.set(0, reps: "3", load: "RPE6"),
                            Factory.set(1, reps: "3", load: "RPE7")
                        ]
                    )
                ]
            )
        }

        private static func upcomingOverviewSession() -> Session {
            Factory.session(
                weekNumber: 2,
                dayNumber: 1,
                exercises: [
                    Factory.exercise(
                        name: "Upcoming Squat",
                        baseName: "Upcoming Squat",
                        coachNote: "Upcoming Session.",
                        order: 0,
                        sets: [
                            Factory.set(0, reps: "5", load: "RPE6"),
                            Factory.set(1, reps: "5", load: "RPE7")
                        ]
                    )
                ]
            )
        }
    }

    private enum WorkoutFixtureFactory {
        @MainActor
        static func block(weeks: [Week]) -> Block {
            let block = Block(tabName: WorkoutFixtureScenarios.blockTab, squatTM: 315, benchTM: 225, deadliftTM: 405)
            block.weeks = weeks
            return block
        }

        @MainActor
        static func week(_ number: Int, sessions: [Session]) -> Week {
            let week = Week(number: number)
            week.sessions = sessions
            return week
        }

        static func session(weekNumber: Int, dayNumber: Int, exercises: [Exercise]) -> Session {
            let order = ((weekNumber - 1) * 4) + dayNumber
            let session = Session(
                dayNumber: dayNumber,
                date: Date(timeIntervalSinceReferenceDate: TimeInterval(order * 86_400))
            )
            session.exercises = exercises
            return session
        }

        static func partiallyLoggedBackSquat() -> Exercise {
            backSquat(
                sets: [
                    loggedSet(0, reps: "5", load: "RPE6", percentOneRM: "75%", weight: 235, rpe: 6),
                    set(1, reps: "5", load: "RPE7", percentOneRM: "80%")
                ]
            )
        }

        static func partiallyLoggedBenchPress() -> Exercise {
            benchPress(
                sets: [
                    loggedSet(0, reps: "5", load: "RPE6", percentOneRM: "70%", weight: 155, rpe: 6),
                    set(1, reps: "5", load: "RPE7", percentOneRM: "75%")
                ]
            )
        }

        static func partiallyLoggedDeadlift() -> Exercise {
            deadlift(
                sets: [
                    loggedSet(0, reps: "3", load: "RPE6", percentOneRM: "75%", weight: 305, rpe: 6),
                    set(1, reps: "3", load: "RPE7", percentOneRM: "80%")
                ]
            )
        }

        static func backSquat(
            sets: [ExerciseSet] = [
                set(0, reps: "5", load: "RPE6", percentOneRM: "75%"),
                set(1, reps: "5", load: "RPE7", percentOneRM: "80%"),
                set(2, reps: "5", load: "RPE8", percentOneRM: "85%")
            ]
        ) -> Exercise {
            exercise(
                name: "Back Squat",
                baseName: "Back Squat",
                coachNote: "Brace hard off the floor, controlled descent.",
                order: 0,
                sets: sets
            )
        }

        static func rdl() -> Exercise {
            exercise(
                name: "2-3:1:0 BB RDL",
                baseName: "BB RDL",
                cadence: "2-3:1:0",
                coachNote: "Start w/ 10 sec hold, proceed to rep range.",
                order: 1,
                sets: [
                    set(0, reps: "8", load: "Drop 17.5%"),
                    set(1, reps: "8", load: "Drop 17.5%")
                ]
            )
        }

        static func benchPress(
            sets: [ExerciseSet] = [
                set(0, reps: "5", load: "RPE6", percentOneRM: "70%"),
                set(1, reps: "5", load: "RPE7", percentOneRM: "75%")
            ]
        ) -> Exercise {
            exercise(name: "Bench Press", baseName: "Bench Press", coachNote: "Pause every rep.", order: 0, sets: sets)
        }

        static func pullUp() -> Exercise {
            exercise(
                name: "Pull-Up",
                baseName: "Pull-Up",
                coachNote: "Use full range.",
                order: 1,
                sets: [
                    set(0, reps: "8", load: "BW"),
                    set(1, reps: "8", load: "BW")
                ]
            )
        }

        static func deadlift(
            sets: [ExerciseSet] = [
                set(0, reps: "3", load: "RPE6", percentOneRM: "75%"),
                set(1, reps: "3", load: "RPE7", percentOneRM: "80%")
            ]
        ) -> Exercise {
            exercise(name: "Deadlift", baseName: "Deadlift", coachNote: "Pull fast from the floor.", order: 0, sets: sets)
        }

        static func accessory(weekNumber: Int, dayNumber: Int) -> Exercise {
            exercise(
                name: "Accessory W\(weekNumber) D\(dayNumber)",
                baseName: "Accessory",
                coachNote: "Controlled reps.",
                order: 0,
                sets: [set(0, reps: "10", load: "RPE6")]
            )
        }

        static func exercise(
            name: String,
            baseName: String,
            cadence: String? = nil,
            coachNote: String,
            order: Int,
            sets: [ExerciseSet]
        ) -> Exercise {
            let exercise = Exercise(name: name, baseName: baseName, cadence: cadence, coachNote: coachNote, order: order)
            exercise.sets = sets
            return exercise
        }

        static func loggedSet(
            _ index: Int,
            reps: String,
            load: String,
            percentOneRM: String? = nil,
            weight: Double,
            rpe: Double
        ) -> ExerciseSet {
            set(
                index,
                reps: reps,
                load: load,
                percentOneRM: percentOneRM,
                state: .logged,
                log: SetLog(weight: .pounds(weight), reps: Int(reps) ?? 0, rpe: rpe)
            )
        }

        static func set(
            _ index: Int,
            reps: String,
            load: String,
            percentOneRM: String? = nil,
            state: SetState = .pending,
            log: SetLog? = nil
        ) -> ExerciseSet {
            let set = ExerciseSet(index: index, prescribedReps: reps, prescribedLoad: load, percentOneRM: percentOneRM, state: state)
            set.setLog = log
            return set
        }
    }
#endif
