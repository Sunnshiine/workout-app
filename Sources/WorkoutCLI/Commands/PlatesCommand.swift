import ArgumentParser
import WorkoutTracker

struct PlatesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plates",
        abstract: "Print the Plate Inventory, or set what Settings' Bar and Plates page sets."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Option(help: "The Bar: 45, 35, or 15kg.")
    var bar: String?

    @Option(help: "Every plate size the gym has, comma separated, as 45,25,10. Empty for none.")
    var plates: String?

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            try home.open().setPlateInventory(bar: bar, plates: plates)
        }
    }
}
