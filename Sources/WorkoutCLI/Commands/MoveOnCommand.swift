import ArgumentParser
import WorkoutTracker

struct MoveOnCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move-on",
        abstract: "Both taps of Move On, requestMoveOnCelebration then dismissMoveOnCelebration, in one process, "
            + "because the celebration lives in memory."
    )

    @OptionGroup var homeOptions: HomeOptions

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            let app = try home.open()
            _ = try app.requestMoveOnCelebration()
            return try app.dismissMoveOnCelebration()
        }
    }
}
