import Foundation

/// Every way a facade verb can fail, with a stable `code` and, where a lookup missed, the
/// addresses that would have hit.
public enum ApplicationError: Error, Equatable, Sendable {
    case notConfigured
    case noBlock
    case invalidAddress(String)
    case invalidSetLog(String)
    case unknownSession(address: String, candidates: [String])
    case sessionUnavailable(String)
    case unknownExercise(address: String, candidates: [String])
    case unknownSet(address: String, candidates: [String])
    case sheetSwitchFailed(String)
    case sheetSwitchRequiresDiscard
    case syncFailed(SyncStateSnapshot)
    case unknownTab(name: String, candidates: [String])

    public var code: String {
        switch self {
        case .notConfigured: "not_configured"
        case .noBlock: "no_block"
        case .invalidAddress: "invalid_address"
        case .invalidSetLog: "invalid_set_log"
        case .unknownSession: "unknown_session"
        case .sessionUnavailable: "session_unavailable"
        case .unknownExercise: "unknown_exercise"
        case .unknownSet: "unknown_set"
        case .sheetSwitchFailed: "sheet_switch_failed"
        case .sheetSwitchRequiresDiscard: "sheet_switch_requires_discard"
        case .syncFailed: "sync_failed"
        case .unknownTab: "unknown_tab"
        }
    }

    public var message: String {
        switch self {
        case .notConfigured:
            "No spreadsheet is selected. Run `workout init --scenario fresh-block`."
        case .noBlock:
            "No Block is cached for the selected spreadsheet. Run `workout sync`."
        case .invalidAddress(let raw):
            "\"\(raw)\" is not an address. Use w<week>d<day>, w<week>d<day>.e<order>, or w<week>d<day>.e<order>.s<index>; "
                + "`workout session` prints them."
        case .invalidSetLog(let raw):
            "\"\(raw)\" is not a Set Log. Use {weight}x{reps}@{RPE}, for example 185x5@8 or BWx12@7."
        case .unknownSession(let address, let candidates):
            "No Session \(address). This Block has \(candidates.count) Sessions; `workout status` lists them."
        case .sessionUnavailable(let address):
            "\(address) is an Unavailable Session: the coach has not uploaded it yet. `workout status` shows which are available."
        case .unknownExercise(let address, let candidates):
            "\(Self.parent(of: address)) has \(candidates.count) Exercises; no Exercise at \(address)."
        case .unknownSet(let address, let candidates):
            "\(Self.parent(of: address)) has \(candidates.count) Sets; no Set at \(address)."
        case .sheetSwitchFailed(let reason):
            "Couldn't select the spreadsheet: \(reason)"
        case .sheetSwitchRequiresDiscard:
            "Pending writes exist for the current spreadsheet. Run `workout flush` before selecting another sheet."
        case .syncFailed(let state):
            "Sync did not complete; the app is \(state.status). Check the workbook and run `workout sync` again."
        case .unknownTab(let name, let candidates):
            "No tab named \"\(name)\". Tabs: \(candidates.joined(separator: ", "))."
        }
    }

    public var candidates: [String]? {
        switch self {
        case .unknownSession(_, let candidates), .unknownExercise(_, let candidates), .unknownSet(_, let candidates),
            .unknownTab(_, let candidates):
            candidates
        case .notConfigured, .noBlock, .invalidAddress, .invalidSetLog, .sessionUnavailable, .sheetSwitchFailed,
            .sheetSwitchRequiresDiscard, .syncFailed:
            nil
        }
    }

    private static func parent(of address: String) -> String {
        address.split(separator: ".").dropLast().joined(separator: ".")
    }
}

extension ApplicationError: LocalizedError {
    public var errorDescription: String? { message }
}
