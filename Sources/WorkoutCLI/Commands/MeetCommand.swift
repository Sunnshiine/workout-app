import ArgumentParser
import Foundation
import WorkoutTracker

struct MeetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "meet",
        abstract: "Plan a Meet and run its day. A Meet stays on this home and never reaches the workbook.",
        subcommands: [Plan.self, Tick.self]
    )

    struct Plan: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the Plan, or change it through the flags given. A new Meet needs --date and --federation."
        )

        @OptionGroup var homeOptions: HomeOptions

        @Option(help: "The Meet's calendar day, as 2026-12-05.")
        var date: String?

        @Option(help: "ipf or usapl.")
        var federation: String?

        @Option(help: "Attempts in kilograms, as 180,190,197.5.")
        var squat: String?

        @Option(help: "Attempts in kilograms.")
        var bench: String?

        @Option(help: "Attempts in kilograms.")
        var deadlift: String?

        @Option(help: "Rack Height, as it reads on the weigh-in sheet.")
        var squatRack: String?

        @Option(help: "Rack Height, as it reads on the weigh-in sheet.")
        var benchRack: String?

        @Option(help: "Warm-up Room Plan, as 60x5@18,100x3@15: kilograms, reps, Attempts Out.")
        var squatWarmups: String?

        @Option(help: "Warm-up Room Plan.")
        var benchWarmups: String?

        @Option(help: "Warm-up Room Plan.")
        var deadliftWarmups: String?

        @Flag(help: "Start each lift with no Warm-up Room Plan from even steps between the bar and its opener.")
        var fillWarmups = false

        @Option(help: "Lifters in the athlete's Flight, which sets Attempts Out after a mark.")
        var lifters: Int?

        @Option(help: "The athlete's estimate of how long the platform takes over one Attempt, in seconds.")
        var secondsPerAttempt: Int?

        private var edit: MeetPlanEdit {
            MeetPlanEdit(
                date: date,
                federation: federation,
                attempts: Self.byLift(squat: squat, bench: bench, deadlift: deadlift),
                rackHeights: Self.byLift(squat: squatRack, bench: benchRack, deadlift: nil),
                warmupRoomPlans: Self.byLift(squat: squatWarmups, bench: benchWarmups, deadlift: deadliftWarmups),
                fillsWarmupRoomPlans: fillWarmups,
                liftersInFlight: lifters,
                secondsPerAttempt: secondsPerAttempt
            )
        }

        private static func byLift(squat: String?, bench: String?, deadlift: String?) -> [String: String] {
            ["squat": squat, "bench": bench, "deadlift": deadlift].compactMapValues { $0 }
        }

        @MainActor
        func run() async throws {
            let home = homeOptions.resolved
            try await Output.run { try home.open().meetPlan(edit) }
        }
    }

    struct Tick: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Take at most one gesture on the day, then print what comes next at $WORKOUT_NOW."
        )

        @OptionGroup var homeOptions: HomeOptions

        @Option(help: "Set the athlete's count of Attempts Out.")
        var attemptsOut: Int?

        @Flag(help: "The lights say good lift. Starts the next Attempt's window.")
        var good = false

        @Flag(help: "The lights say no lift. Starts the next Attempt's window.")
        var noLift = false

        @Option(help: "The next Attempt's card, in kilograms.")
        var submit: String?

        @Flag(help: "The window closed with no card, so the table's own entry goes in.")
        var tableEntry = false

        @Flag(help: "Take no more Attempts in this lift.")
        var pass = false

        @Flag(help: "Take back the last mark or pass.")
        var undo = false

        @Option(help: "Change the Attempt on deck, in kilograms, where the rules allow one.")
        var change: String?

        private var gestures: [MeetGesture] {
            let named: [MeetGesture?] = [
                attemptsOut.map(MeetGesture.attemptsOut),
                submit.map(MeetGesture.submit),
                change.map(MeetGesture.change)
            ]
            let flagged: [(isSet: Bool, gesture: MeetGesture)] = [
                (good, .good), (noLift, .noLift), (tableEntry, .acceptTableEntry), (pass, .pass), (undo, .undo)
            ]
            return named.compactMap { $0 } + flagged.filter(\.isSet).map(\.gesture)
        }

        func validate() throws {
            guard gestures.count <= 1 else { throw ValidationError("Give at most one gesture.") }
        }

        @MainActor
        func run() async throws {
            let home = homeOptions.resolved
            let gesture = gestures.first ?? .read
            try await Output.run { try home.open().meetTick(gesture) }
        }
    }
}
