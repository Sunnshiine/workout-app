import Foundation

/// What a missed lookup was looking for. The raw value is the wire `code` the CLI prints, so a
/// reader grepping for `unknown_set` lands here.
public enum LookupKind: String, Sendable {
    case session = "unknown_session"
    case exercise = "unknown_exercise"
    case set = "unknown_set"
    case tab = "unknown_tab"

    func message(name: String, candidates: [String]) -> String {
        switch self {
        case .session:
            "No Session \(name). This Block has \(candidates.count) Sessions; `workout status` lists them."
        case .exercise:
            "\(Self.parent(of: name)) has \(candidates.count) Exercises; no Exercise at \(name)."
        case .set:
            "\(Self.parent(of: name)) has \(candidates.count) Sets; no Set at \(name)."
        case .tab:
            "No tab named \"\(name)\". Tabs: \(candidates.joined(separator: ", "))."
        }
    }

    private static func parent(of address: String) -> String {
        address.split(separator: ".").dropLast().joined(separator: ".")
    }
}

/// Every way a facade verb can fail, with a stable `code` and, where a lookup missed, the
/// addresses that would have hit.
public enum ApplicationError: Error, Equatable, Sendable {
    case notConfigured
    case noBlock
    case invalidAddress(String)
    case invalidSetLog(String)
    case notFound(LookupKind, name: String, candidates: [String])
    case sessionUnavailable(String)
    case sheetSwitchFailed(String)
    case sheetSwitchRequiresDiscard
    case syncFailed(SyncStateSnapshot)

    public var code: String {
        switch self {
        case .notConfigured: "not_configured"
        case .noBlock: "no_block"
        case .invalidAddress: "invalid_address"
        case .invalidSetLog: "invalid_set_log"
        case .notFound(let kind, _, _): kind.rawValue
        case .sessionUnavailable: "session_unavailable"
        case .sheetSwitchFailed: "sheet_switch_failed"
        case .sheetSwitchRequiresDiscard: "sheet_switch_requires_discard"
        case .syncFailed: "sync_failed"
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
        case .notFound(let kind, let name, let candidates):
            kind.message(name: name, candidates: candidates)
        case .sessionUnavailable(let address):
            "\(address) is an Unavailable Session: the coach has not uploaded it yet. `workout status` shows which are available."
        case .sheetSwitchFailed(let reason):
            "Couldn't select the spreadsheet: \(reason)"
        case .sheetSwitchRequiresDiscard:
            "Pending writes exist for the current spreadsheet. Run `workout flush` before selecting another sheet."
        case .syncFailed(let state):
            "Sync did not complete; the app is \(state.status). Check the workbook and run `workout sync` again."
        }
    }

    public var candidates: [String]? {
        switch self {
        case .notFound(_, _, let candidates):
            candidates
        case .notConfigured, .noBlock, .invalidAddress, .invalidSetLog, .sessionUnavailable, .sheetSwitchFailed,
            .sheetSwitchRequiresDiscard, .syncFailed:
            nil
        }
    }
}

extension ApplicationError: LocalizedError {
    public var errorDescription: String? { message }
}
