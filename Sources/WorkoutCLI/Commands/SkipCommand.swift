import ArgumentParser
import WorkoutTracker

struct SkipCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skip",
        abstract: "Skip a Set through WorkoutStore.skip. Enqueues the Sheet write(s); run `flush` to send them."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Argument(help: "A Set address such as w1d1.e0.s0.")
    var address: String

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            guard let parsed = SetAddress(address) else { throw ApplicationError.invalidAddress(address) }
            return try home.open().skip(parsed)
        }
    }
}
