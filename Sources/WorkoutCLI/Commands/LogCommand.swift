import ArgumentParser
import WorkoutTracker

struct LogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Log a Set through WorkoutStore.log. Enqueues the Sheet write(s); run `flush` to send them."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Argument(help: "A Set address such as w1d1.e0.s0.")
    var address: String

    @Argument(help: "A Set Log such as 185x5@8 or BWx12@7.")
    var setLog: String

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            guard let parsed = SetAddress(address) else { throw ApplicationError.invalidAddress(address) }
            return try home.open().log(parsed, setLog: setLog)
        }
    }
}
