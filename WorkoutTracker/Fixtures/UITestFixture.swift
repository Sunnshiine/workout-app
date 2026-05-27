#if DEBUG
    import Foundation
    import SwiftData

    /// Boots the app into a deterministic, populated `SessionView` for unattended UI verification.
    ///
    /// Activated by launching with the `-UITEST_FIXTURE` argument. Uses an in-memory store and a
    /// faked sign-in so it never touches real data, Google auth, or the network — the Ralph loop
    /// can screenshot a known screen without clearing the OAuth onboarding wall.
    enum UITestFixture {
        static var isEnabled: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_FIXTURE")
        }

        static let sheetURL = "https://docs.google.com/spreadsheets/d/FIXTURE/edit"
        private static let defaultsSuiteName = "WorkoutTracker.UITestFixture"

        /// An in-memory container seeded with one sample Block.
        @MainActor
        static func makeContainer() -> ModelContainer {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            let container = try! ModelContainer(
                for: Block.self,
                PendingWrite.self,
                LastPerformedEntry.self,
                configurations: config
            )
            seed(into: container.mainContext)
            return container
        }

        static func makeDefaults() -> UserDefaults {
            let defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            return defaults
        }

        static func makeSheetsClient() -> any SheetsClient {
            FixtureSheetsClient()
        }

        @MainActor
        private static func seed(into context: ModelContext) {
            let block = Block(tabName: "Block 27", squatTM: 315, benchTM: 225, deadliftTM: 405)
            block.weeks = (1...4).map { weekNumber in
                let week = Week(number: weekNumber)
                week.sessions = (1...4).map { dayNumber in
                    session(weekNumber: weekNumber, dayNumber: dayNumber)
                }
                return week
            }

            context.insert(block)
            context.insert(
                LastPerformedEntry(
                    fullName: "Back Squat",
                    baseName: "Back Squat",
                    result: SetLog(weight: .pounds(255), reps: 5, rpe: 7),
                    performedOn: Date(timeIntervalSinceReferenceDate: 100),
                    source: "Block 26 · W4 D3"
                )
            )
            // swiftlint:disable:next force_try
            try! context.save()
        }

        private static func session(weekNumber: Int, dayNumber: Int) -> Session {
            let order = ((weekNumber - 1) * 4) + dayNumber
            let session = Session(
                dayNumber: dayNumber,
                date: Date(timeIntervalSinceReferenceDate: TimeInterval(order * 86_400))
            )

            session.exercises =
                switch (weekNumber, dayNumber) {
                case (1, 1):
                    [backSquat(), rdl()]
                case (1, 2):
                    [benchPress(), pullUp()]
                case (1, 3):
                    [deadlift()]
                default:
                    [accessory(weekNumber: weekNumber, dayNumber: dayNumber)]
                }
            return session
        }

        private static func backSquat() -> Exercise {
            exercise(
                name: "Back Squat",
                baseName: "Back Squat",
                coachNote: "Brace hard off the floor, controlled descent.",
                order: 0,
                sets: [
                    set(0, reps: "5", load: "RPE6", percentOneRM: "75%"),
                    set(1, reps: "5", load: "RPE7", percentOneRM: "80%"),
                    set(2, reps: "5", load: "RPE8", percentOneRM: "85%")
                ]
            )
        }

        private static func rdl() -> Exercise {
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

        private static func benchPress() -> Exercise {
            exercise(
                name: "Bench Press",
                baseName: "Bench Press",
                coachNote: "Pause every rep.",
                order: 0,
                sets: [
                    set(0, reps: "5", load: "RPE6", percentOneRM: "70%"),
                    set(1, reps: "5", load: "RPE7", percentOneRM: "75%")
                ]
            )
        }

        private static func pullUp() -> Exercise {
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

        private static func deadlift() -> Exercise {
            exercise(
                name: "Deadlift",
                baseName: "Deadlift",
                coachNote: "Pull fast from the floor.",
                order: 0,
                sets: [
                    set(0, reps: "3", load: "RPE6", percentOneRM: "75%"),
                    set(1, reps: "3", load: "RPE7", percentOneRM: "80%")
                ]
            )
        }

        private static func accessory(weekNumber: Int, dayNumber: Int) -> Exercise {
            exercise(
                name: "Accessory W\(weekNumber) D\(dayNumber)",
                baseName: "Accessory",
                coachNote: "Controlled reps.",
                order: 0,
                sets: [set(0, reps: "10", load: "RPE6")]
            )
        }

        private static func exercise(
            name: String,
            baseName: String,
            cadence: String? = nil,
            coachNote: String,
            order: Int,
            sets: [ExerciseSet]
        ) -> Exercise {
            let exercise = Exercise(
                name: name,
                baseName: baseName,
                cadence: cadence,
                coachNote: coachNote,
                order: order
            )
            exercise.sets = sets
            return exercise
        }

        private static func set(
            _ index: Int,
            reps: String,
            load: String,
            percentOneRM: String? = nil
        ) -> ExerciseSet {
            ExerciseSet(
                index: index,
                prescribedReps: reps,
                prescribedLoad: load,
                percentOneRM: percentOneRM,
                state: .pending
            )
        }
    }

    private struct FixtureSheetsClient: SheetsClient {
        func listTabTitles(spreadsheetId: String) async throws -> [String] {
            ["Block 27"]
        }

        func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
            throw SheetsError.malformedResponse
        }

        func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
    }
#endif
