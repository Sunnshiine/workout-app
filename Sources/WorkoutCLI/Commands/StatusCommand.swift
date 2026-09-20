import ArgumentParser
import WorkoutTracker

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Sync state, pending writes, the Current Session, and the Session index."
    )

    @OptionGroup var homeOptions: HomeOptions

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run { try home.open().snapshot() }
    }
}
