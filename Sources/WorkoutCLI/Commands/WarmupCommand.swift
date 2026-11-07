import ArgumentParser
import WorkoutTracker

struct WarmupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "warmup",
        abstract: "Print a Set's Warm-up Ramp: its steps and the Plate Load of each. Writes nothing."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Argument(help: "A Set address such as w1d1.e0.s0.")
    var address: String

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            guard let parsed = SetAddress(address) else { throw ApplicationError.invalidAddress(address) }
            return try home.open().warmupRamp(parsed)
        }
    }
}
