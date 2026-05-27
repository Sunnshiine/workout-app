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

        @MainActor
        private static func seed(into context: ModelContext) {
            let block = Block(tabName: "Block 27", squatTM: 315, benchTM: 225, deadliftTM: 405)
            let week = Week(number: 1)
            let session = Session(dayNumber: 1, date: Date())

            let squat = Exercise(
                name: "Back Squat",
                baseName: "Back Squat",
                cadence: nil,
                coachNote: "Brace hard off the floor, controlled descent.",
                order: 0
            )
            squat.sets = [
                ExerciseSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE6", percentOneRM: "75%", state: .pending),
                ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE7", percentOneRM: "80%", state: .pending),
                ExerciseSet(index: 2, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: "85%", state: .pending)
            ]

            let rdl = Exercise(
                name: "2-3:1:0 BB RDL",
                baseName: "BB RDL",
                cadence: "2-3:1:0",
                coachNote: "Start w/ 10 sec hold, proceed to rep range.",
                order: 1
            )
            rdl.sets = [
                ExerciseSet(index: 0, prescribedReps: "8", prescribedLoad: "Drop 17.5%", percentOneRM: nil, state: .pending),
                ExerciseSet(index: 1, prescribedReps: "8", prescribedLoad: "Drop 17.5%", percentOneRM: nil, state: .pending)
            ]

            session.exercises = [squat, rdl]
            week.sessions = [session]
            block.weeks = [week]

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
    }
#endif
