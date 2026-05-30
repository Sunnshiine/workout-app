import Foundation

struct CurrentSessionDebugInfo: Equatable, Sendable {
    let currentBlockTab: String
    let sheetDerivedSession: String
    let manualOverrideSession: String
    let displayedSession: String
    let resolvedCurrentSession: String
    let reason: String
    let localOnlyNote: String?

    var copyText: String {
        [
            "Current Session Debug Info",
            "Current Block Tab: \(currentBlockTab)",
            "Sheet-derived Session: \(sheetDerivedSession)",
            "Manual Current Session Override: \(manualOverrideSession)",
            "Displayed Session: \(displayedSession)",
            "Resolved Current Session: \(resolvedCurrentSession)",
            "Reason: \(reason)",
            localOnlyNote
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

struct PendingWriteDiagnostic: Equatable, Identifiable, Sendable {
    let id: UUID
    let block: String
    let week: String
    let day: String
    let exercise: String
    let set: String
    let column: String
    let value: String
    let status: String
    let error: String?

    init(write: PendingWrite) {
        id = write.id
        block = write.blockTab
        week = "Week \(write.week)"
        day = "Day \(write.day)"
        exercise = write.exerciseName
        set = "Set \(write.setIndex + 1)"
        column = Self.columnLabel(for: write.column)
        value = write.valueToWrite ?? "Delete"
        status = Self.statusLabel(for: write.status)
        error = write.lastError
    }

    private static func columnLabel(for column: PendingWriteColumn) -> String {
        switch column {
        case .notes:
            "Notes"
        case .lastSetRPE:
            "Last Set RPE"
        }
    }

    private static func statusLabel(for status: PendingWriteStatus) -> String {
        switch status {
        case .pending:
            "Pending"
        case .conflict:
            "Conflict"
        }
    }
}

extension SyncCoordinator {
    func pendingWriteDiagnostics() throws -> [PendingWriteDiagnostic] {
        try fetchPendingWriteRecords().map(PendingWriteDiagnostic.init)
    }
}
