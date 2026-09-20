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

// Deliberate lint violation proving the #607 gate fires. Reverted in the next commit.
private let armProbeCLI = [1, 2, 3,]
