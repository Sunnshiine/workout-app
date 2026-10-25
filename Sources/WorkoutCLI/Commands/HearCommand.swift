import ArgumentParser
import Foundation
import Synchronization
import WorkoutTracker

struct HearCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hear",
        abstract: "Log or skip a Set from a recording, heard by the app's on-device speech-to-text. "
            + "Enqueues the Sheet write(s); run `flush` to send them."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Argument(help: "A Set address such as w1d1.e0.s0.")
    var address: String

    @Argument(help: "An audio file, such as one `say -o set.aiff \"185 for 5 at 8\"` writes.")
    var recording: String

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            guard let parsed = SetAddress(address) else { throw ApplicationError.invalidAddress(address) }
            guard #available(macOS 26, *) else { throw ApplicationError.speechUnavailable }
            return try await home.open().hear(URL(fileURLWithPath: recording), at: parsed, installing: AssetProgress().report)
        } verdict: { heard in
            guard let rejection = heard.report.rejection else { return }
            throw ApplicationError.spokenSetRejected(heard.report.heard, reason: rejection.reason)
        }
    }
}

/// Prints the speech assets' install to stderr as JSON lines, one per whole percent.
private final class AssetProgress: Sendable {
    private let lastPercent = Mutex(-1)

    func report(_ fraction: Double) {
        let percent = Int(fraction * 100)
        let isNew = lastPercent.withLock { last in
            defer { last = percent }
            return last != percent
        }
        guard isNew else { return }
        FileHandle.standardError.write(Data("{\"installingSpeechAssets\":{\"percent\":\(percent)}}\n".utf8))
    }
}
