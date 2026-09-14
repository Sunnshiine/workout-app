import ArgumentParser
import WorkoutTracker

struct SessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "One Session with every Exercise and Set, each carrying its address. Defaults to the Current Session."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Argument(help: "A Session address such as w1d1.")
    var address: String?

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            let parsed = try address.map { raw in
                guard let parsed = SessionAddress(raw) else { throw ApplicationError.invalidAddress(raw) }
                return parsed
            }
            return try home.open().session(parsed)
        }
    }
}
