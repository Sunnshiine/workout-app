import ArgumentParser
import Foundation
import WorkoutTracker

enum ExitClass: Int32 {
    case domain = 1
    case environment = 3
    case conflict = 4
    case internalError = 70
}

enum CLIError: Error {
    case environment(String)
    case invalidCell(String)
    case conflict(code: String, messages: [String])
}

struct ErrorPayload: Encodable {
    let code: String
    let message: String
    let candidates: [String]?
}

struct Failure {
    let payload: ErrorPayload
    let exitClass: ExitClass

    init(_ error: any Error) {
        switch error {
        case let error as ApplicationError:
            payload = ErrorPayload(code: error.code, message: error.message, candidates: error.candidates)
            exitClass = Self.exitClass(for: error)
        case CLIError.environment(let message):
            payload = ErrorPayload(code: "environment", message: message, candidates: nil)
            exitClass = .environment
        case CLIError.invalidCell(let raw):
            payload = ErrorPayload(
                code: "invalid_cell",
                message: "\"\(raw)\" is not an A1 cell reference. Use a column and a row, for example K15.",
                candidates: nil
            )
            exitClass = .domain
        case CLIError.conflict(let code, let messages):
            payload = ErrorPayload(code: code, message: messages.joined(separator: "\n"), candidates: nil)
            exitClass = .conflict
        case is DecodingError, is CocoaError:
            payload = ErrorPayload(code: "environment", message: String(describing: error), candidates: nil)
            exitClass = .environment
        default:
            payload = ErrorPayload(code: "internal", message: String(describing: error), candidates: nil)
            exitClass = .internalError
        }
    }

    private static func exitClass(for error: ApplicationError) -> ExitClass {
        switch error {
        case .notConfigured, .sheetSwitchFailed, .syncFailed(.offline), .syncFailed(.idle), .syncFailed(.syncing),
            .syncFailed(.pendingWrites):
            .environment
        case .syncFailed(.conflict):
            .conflict
        case .noBlock, .invalidAddress, .invalidSetLog, .unknownSession, .sessionUnavailable, .unknownExercise, .unknownSet,
            .sheetSwitchRequiresDiscard, .unknownTab:
            .domain
        }
    }
}

enum Output {
    private static var stdoutEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var stderrEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    @MainActor
    static func run<Value: Encodable>(
        _ body: @MainActor () async throws -> Value,
        verdict: (Value) throws -> Void = { _ in }
    ) async throws {
        let value: Value
        do {
            value = try await body()
        } catch {
            throw fail(error)
        }
        let data = try stdoutEncoder.encode(value)
        FileHandle.standardOutput.write(data + Data("\n".utf8))
        do {
            try verdict(value)
        } catch {
            throw fail(error)
        }
    }

    private static func fail(_ error: any Error) -> ExitCode {
        let failure = Failure(error)
        if let data = try? stderrEncoder.encode(["error": failure.payload]) {
            FileHandle.standardError.write(data + Data("\n".utf8))
        }
        return ExitCode(failure.exitClass.rawValue)
    }
}
