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

/// Every way a facade verb can fail, carried as the facts a boundary needs: a stable wire `code`, a
/// human `message`, the addresses that would have hit, and the class of failure. Build one with the
/// verbs below; the initializer is internal, so no failure can exist missing one of the four facts.
public struct ApplicationError: Error, Equatable, Sendable {
    /// Whose fault the failure is, and therefore what the caller can do about it. The CLI turns
    /// this into its exit code.
    public enum Kind: String, Sendable, CaseIterable {
        /// The machine, the sheet, or the network is not ready. The same request may succeed later.
        case environment
        /// The request itself is wrong. Retrying it unchanged fails again.
        case domain
        /// The Sheet moved under a pending write. Only the athlete can resolve it.
        case conflict
    }

    public let code: String
    public let message: String
    public let candidates: [String]?
    public let kind: Kind

    init(code: String, message: String, candidates: [String]? = nil, kind: Kind) {
        self.code = code
        self.message = message
        self.candidates = candidates
        self.kind = kind
    }
}

extension ApplicationError {
    public static let notConfigured = ApplicationError(
        code: "not_configured",
        message: "No spreadsheet is selected. Run `workout init --scenario fresh-block`.",
        kind: .environment
    )

    public static let noBlock = ApplicationError(
        code: "no_block",
        message: "No Block is cached for the selected spreadsheet. Run `workout sync`.",
        kind: .domain
    )

    public static let sheetSwitchRequiresDiscard = ApplicationError(
        code: "sheet_switch_requires_discard",
        message: "Pending writes exist for the current spreadsheet. Run `workout flush` before selecting another sheet.",
        kind: .domain
    )

    public static func invalidAddress(_ raw: String) -> ApplicationError {
        ApplicationError(
            code: "invalid_address",
            message: "\"\(raw)\" is not an address. Use w<week>d<day>, w<week>d<day>.e<order>, or "
                + "w<week>d<day>.e<order>.s<index>; `workout session` prints them.",
            kind: .domain
        )
    }

    public static func invalidSetLog(_ raw: String) -> ApplicationError {
        ApplicationError(
            code: "invalid_set_log",
            message: "\"\(raw)\" is not a Set Log. Use {weight}x{reps}@{RPE}, for example 185x5@8 or BWx12@7.",
            kind: .domain
        )
    }

    public static func notFound(_ lookup: LookupKind, name: String, candidates: [String]) -> ApplicationError {
        ApplicationError(
            code: lookup.rawValue,
            message: lookup.message(name: name, candidates: candidates),
            candidates: candidates,
            kind: .domain
        )
    }

    public static func sessionUnavailable(_ address: String) -> ApplicationError {
        ApplicationError(
            code: "session_unavailable",
            message: "\(address) is an Unavailable Session: the coach has not uploaded it yet. "
                + "`workout status` shows which are available.",
            kind: .domain
        )
    }

    public static func sheetSwitchFailed(_ reason: String) -> ApplicationError {
        ApplicationError(
            code: "sheet_switch_failed",
            message: "Couldn't select the spreadsheet: \(reason)",
            kind: .environment
        )
    }

    public static func syncFailed(_ state: SyncStateSnapshot) -> ApplicationError {
        let kind: Kind =
            switch state {
            case .conflict: .conflict
            case .idle, .syncing, .offline, .pendingWrites: .environment
            }
        return ApplicationError(
            code: "sync_failed",
            message:
                "Sync did not complete; the app is \(state.status). Check the workbook and run `workout sync` again.",
            kind: kind
        )
    }
}

extension ApplicationError: LocalizedError {
    public var errorDescription: String? { message }
}
