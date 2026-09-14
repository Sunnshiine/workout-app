import ArgumentParser
import CryptoKit
import Foundation
import WorkoutTracker

struct HomeOptions: ParsableArguments {
    @Option(help: "State directory. Defaults to $WORKOUT_HOME, else ./.workout-cli.")
    var home: String?

    var resolved: Home {
        Home(path: home ?? ProcessInfo.processInfo.environment["WORKOUT_HOME"] ?? ".workout-cli")
    }
}

struct Manifest: Codable {
    static let currentVersion = 1

    var version = Manifest.currentVersion
    let scenario: String
    let spreadsheetId: String
    let createdAt: Date
}

struct Home {
    let url: URL

    init(path: String) {
        url = URL(fileURLWithPath: path).standardizedFileURL
    }

    var manifestURL: URL { url.appendingPathComponent("manifest.json") }
    var workbookURL: URL { url.appendingPathComponent("workbook.json") }

    var defaultsSuite: String {
        let digest = SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return "WorkoutTracker.cli.\(digest.prefix(16))"
    }

    @MainActor
    func open() throws -> WorkoutApplication {
        guard let manifest = try ownManifest() else {
            throw CLIError.environment("No workout home at \(url.path). Run `workout init --scenario fresh-block`.")
        }
        guard manifest.version == Manifest.currentVersion else {
            throw CLIError.environment(
                "\(url.path) was made by a different version of workout (manifest version \(manifest.version)). Run `workout init` again."
            )
        }
        let environment = try AppEnvironment.directory(
            url,
            workbookFile: workbookURL,
            defaults: try defaults(),
            now: try FrozenClock.resolve()
        )
        return try WorkoutApplication(environment: environment)
    }

    func reset(scenario: WorkbookScenario, workbook: LocalWorkbook) throws -> Manifest {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CLIError.environment("\(url.path) is a file, not a directory; refusing to replace it.")
            }
            let isEmpty = try fileManager.contentsOfDirectory(atPath: url.path).isEmpty
            let isOurs = try ownManifest() != nil
            guard isEmpty || isOurs else {
                throw CLIError.environment("\(url.path) is not empty and has no workout manifest.json; refusing to wipe it.")
            }
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        let manifest = Manifest(
            scenario: scenario.rawValue,
            spreadsheetId: workbook.spreadsheetId,
            createdAt: try FrozenClock.resolve()()
        )
        try JSONEncoder.manifest.encode(manifest).write(to: manifestURL, options: .atomic)
        try workbook.write(to: workbookURL)
        try defaults().removePersistentDomain(forName: defaultsSuite)
        return manifest
    }

    private func ownManifest() throws -> Manifest? {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        return try? JSONDecoder.manifest.decode(Manifest.self, from: Data(contentsOf: manifestURL))
    }

    private func defaults() throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
            throw CLIError.environment("Could not open the defaults suite \(defaultsSuite).")
        }
        return defaults
    }
}

enum FrozenClock {
    static func resolve() throws -> @Sendable () -> Date {
        guard let raw = ProcessInfo.processInfo.environment["WORKOUT_NOW"] else { return { Date() } }
        guard let date = ISO8601DateFormatter().date(from: raw) else {
            throw CLIError.environment("WORKOUT_NOW is not an ISO-8601 date: \"\(raw)\". Use 2026-05-28T20:26:40Z.")
        }
        return { date }
    }
}

extension JSONEncoder {
    static var manifest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var manifest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
