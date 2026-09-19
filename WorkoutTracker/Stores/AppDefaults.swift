import Foundation
import OSLog

private let appDefaultsLogger = Logger(subsystem: "WorkoutTracker", category: "AppDefaults")

@MainActor
final class AppDefaults {
    private enum Backing {
        case standardUserDefaults
        case owned(values: [String: Value], file: URL?)
    }

    private var backing: Backing

    private nonisolated init(backing: Backing) {
        self.backing = backing
    }

    nonisolated static func device() -> AppDefaults {
        AppDefaults(backing: .standardUserDefaults)
    }

    nonisolated static func inMemory() -> AppDefaults {
        AppDefaults(backing: .owned(values: [:], file: nil))
    }

    nonisolated static func file(_ url: URL) throws -> AppDefaults {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AppDefaults(backing: .owned(values: [:], file: url))
        }
        let values = try JSONDecoder().decode([String: Value].self, from: Data(contentsOf: url))
        return AppDefaults(backing: .owned(values: values, file: url))
    }

    func string(forKey key: String) -> String? {
        switch backing {
        case .standardUserDefaults:
            return UserDefaults.standard.string(forKey: key)
        case .owned(let values, _):
            guard case .string(let string) = values[key] else { return nil }
            return string
        }
    }

    func integer(forKey key: String) -> Int? {
        switch backing {
        case .standardUserDefaults:
            guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
            return UserDefaults.standard.integer(forKey: key)
        case .owned(let values, _):
            guard case .int(let int) = values[key] else { return nil }
            return int
        }
    }

    func hasValue(forKey key: String) -> Bool {
        switch backing {
        case .standardUserDefaults:
            UserDefaults.standard.object(forKey: key) != nil
        case .owned(let values, _):
            values[key] != nil
        }
    }

    var keys: Set<String> {
        switch backing {
        case .standardUserDefaults:
            Set(UserDefaults.standard.dictionaryRepresentation().keys)
        case .owned(let values, _):
            Set(values.keys)
        }
    }

    func set(_ value: String, forKey key: String) {
        switch backing {
        case .standardUserDefaults:
            UserDefaults.standard.set(value, forKey: key)
        case .owned(var values, let file):
            values[key] = .string(value)
            replace(with: values, file: file)
        }
    }

    func set(_ value: Int, forKey key: String) {
        switch backing {
        case .standardUserDefaults:
            UserDefaults.standard.set(value, forKey: key)
        case .owned(var values, let file):
            values[key] = .int(value)
            replace(with: values, file: file)
        }
    }

    func removeValue(forKey key: String) {
        switch backing {
        case .standardUserDefaults:
            UserDefaults.standard.removeObject(forKey: key)
        case .owned(var values, let file):
            values[key] = nil
            replace(with: values, file: file)
        }
    }

    private func replace(with values: [String: Value], file: URL?) {
        backing = .owned(values: values, file: file)
        guard let file else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(values).write(to: file, options: .atomic)
        } catch {
            appDefaultsLogger.error("Could not write settings to \(file.path): \(error.localizedDescription)")
        }
    }
}

private enum Value: Codable {
    case string(String)
    case int(Int)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .int(let int):
            try container.encode(int)
        }
    }
}
