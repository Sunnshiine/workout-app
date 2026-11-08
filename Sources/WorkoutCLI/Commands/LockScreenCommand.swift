import ArgumentParser
import WorkoutTracker

struct LockScreenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lock-screen",
        abstract: "What the Lock Screen's card offers for the Current Session's active Set."
    )

    @OptionGroup var homeOptions: HomeOptions

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run { try home.open().lockScreenOffer() }
    }
}

struct RPEChipCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rpe-chip",
        abstract: "Press an RPE Chip after the Reps Chip. Enqueues the Sheet write; run `flush` to send it."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Argument(help: "The `setIdentity` `lock-screen` printed.")
    var setIdentity: String

    @Argument(help: "The Reps Chip pressed first, from 1 to 100.")
    var reps: Int

    @Argument(help: "An RPE from the Table, such as 7 or 7.5.")
    var rpe: String

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            try home.open().pressRPEChip(setIdentity: setIdentity, reps: reps, rpe: rpe)
        } verdict: { report in
            guard let reason = report.reason else { return }
            throw ApplicationError.rpeChipRefused(reason)
        }
    }
}
