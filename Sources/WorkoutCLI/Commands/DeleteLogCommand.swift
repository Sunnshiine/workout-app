import ArgumentParser
import WorkoutTracker

struct DeleteLogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-log",
        abstract: "Clear a Set through WorkoutStore.deleteLog. Enqueues the Sheet write; run `flush` to send it. "
            + "A Pending Set writes nothing."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Argument(help: "A Set address such as w1d1.e0.s0.")
    var address: String

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            guard let parsed = SetAddress(address) else { throw ApplicationError.invalidAddress(address) }
            return try home.open().deleteLog(parsed)
        }
    }
}
