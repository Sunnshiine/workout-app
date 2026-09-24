import Foundation

struct SheetWriteAuditDetails: Sendable, Equatable {
    let selectedA1Target: String?
    let rowScanDetails: String
    let currentValue: String?
    let valueCheckOutcome: String
}

extension SheetWritePlanner {
    func auditDetails(
        for request: SheetWriteRequest,
        target: SheetWriteTarget,
        in snapshot: SheetWritePlanningSnapshot
    ) -> SheetWriteAuditDetails {
        let currentValue = currentValueForAudit(for: request, target: target, in: snapshot)
        let valueCheckOutcome =
            currentValue == request.expectedCurrentValue
            ? "Current value matched expected '\(request.expectedCurrentValue)'."
            : "Expected '\(request.expectedCurrentValue)', found '\(currentValue)'."

        return SheetWriteAuditDetails(
            selectedA1Target: singleCellRange(tabName: target.tabName, row: target.row, col: target.col),
            rowScanDetails: rowScanDetails(for: request, selectedRow: target.row, in: snapshot),
            currentValue: currentValue,
            valueCheckOutcome: valueCheckOutcome
        )
    }

    func auditDetails(
        for request: SheetWriteRequest,
        error: SheetWriterError,
        in snapshot: SheetWritePlanningSnapshot,
        target: SheetWriteTarget?
    ) -> SheetWriteAuditDetails {
        if case .unexpectedCurrentValue(let expected, let actual) = error {
            return SheetWriteAuditDetails(
                selectedA1Target: target.map { singleCellRange(tabName: $0.tabName, row: $0.row, col: $0.col) },
                rowScanDetails: rowScanDetails(for: request, selectedRow: target?.row, in: snapshot),
                currentValue: actual,
                valueCheckOutcome: "Expected '\(expected)', found '\(actual)'."
            )
        }

        if let target {
            return auditDetails(for: request, target: target, in: snapshot)
        }

        return SheetWriteAuditDetails(
            selectedA1Target: nil,
            rowScanDetails: rowScanDetails(for: request, selectedRow: nil, in: snapshot),
            currentValue: nil,
            valueCheckOutcome: "Not checked because no target was selected."
        )
    }

    private func currentValueForAudit(
        for request: SheetWriteRequest,
        target: SheetWriteTarget,
        in snapshot: SheetWritePlanningSnapshot
    ) -> String {
        let actual = snapshot.grid.cell(row: target.row, col: target.col).trimmed
        guard let placement = placement(for: request, target: target, in: snapshot) else { return actual }

        return placement.listPosition.map { SetLogList(cell: actual).token(at: $0) } ?? actual
    }

    private func rowScanDetails(
        for request: SheetWriteRequest,
        selectedRow: Int?,
        in snapshot: SheetWritePlanningSnapshot
    ) -> String {
        let session = "Week \(request.week), Day \(request.day)"
        let narration: SetLogPlacementNarration
        switch addressing(for: request, in: snapshot) {
        case .weekNotFound, .dayNotFound:
            return "No row selected: \(session) was not found."
        case .columnNotFound(let header):
            return "No row selected: \(session) has no \(header) column."
        case .exerciseNotFound:
            return "No row selected: \(request.exerciseName) was not found in \(session)."
        case .lastSetRPE(let anchor, _):
            narration = .lastSetRPE(anchor: anchor)
        case .setLog(let anchor, let resolution):
            narration = resolution.rowScanNarration(setIndex: request.setIndex, anchor: anchor)
        }
        return narration.text(selectedRow: selectedRow, in: snapshot.snapshot)
    }
}

struct CurrentSessionDebugInfo: Equatable, Sendable {
    let currentBlockTab: String
    let sheetDerivedSession: String
    let manualOverrideSession: String
    let viewedSession: String
    let resolvedCurrentSession: String
    let reason: String
    let localOnlyNote: String?

    var copyText: String {
        [
            "Current Session Debug Info",
            "Current Block Tab: \(currentBlockTab)",
            "Sheet-derived Session: \(sheetDerivedSession)",
            "Manual Current Session Override: \(manualOverrideSession)",
            "Displayed Session: \(viewedSession)",
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

    static func columnLabel(for column: PendingWriteColumn) -> String {
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

struct WriteTargetAuditDiagnostic: Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let semanticTarget: String
    let target: String
    let rowScanDetails: String
    let valueCheckOutcome: String
    let status: String
    let message: String?

    init(entry: WriteTargetAuditEntry) {
        id = entry.id
        createdAt = entry.createdAt
        semanticTarget = [
            entry.blockTab,
            "Week \(entry.week)",
            "Day \(entry.day)",
            entry.exerciseName,
            "Set \(entry.setIndex + 1)",
            PendingWriteDiagnostic.columnLabel(for: entry.column)
        ].joined(separator: ", ")
        target = entry.selectedA1Target ?? "No target selected"
        rowScanDetails = entry.rowScanDetails
        valueCheckOutcome = entry.valueCheckOutcome
        status = Self.statusLabel(for: entry.finalStatus)
        message = entry.message
    }

    static func copyText(for diagnostics: [WriteTargetAuditDiagnostic]) -> String {
        guard !diagnostics.isEmpty else { return "Write Target Audit Log\nNo audit entries" }
        let entries = diagnostics.map { diagnostic in
            [
                diagnostic.semanticTarget,
                "Selected target: \(diagnostic.target)",
                "Row scan: \(diagnostic.rowScanDetails)",
                "Value check: \(diagnostic.valueCheckOutcome)",
                "Final status: \(diagnostic.status)",
                diagnostic.message.map { "Message: \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        }
        return (["Write Target Audit Log"] + entries).joined(separator: "\n\n")
    }

    private static func statusLabel(for status: WriteTargetAuditStatus) -> String {
        switch status {
        case .succeeded:
            "Succeeded"
        case .conflict:
            "Conflict"
        }
    }
}

extension SyncCoordinator {
    func pendingWriteDiagnostics() throws -> [PendingWriteDiagnostic] {
        try fetchPendingWriteRecords().map(PendingWriteDiagnostic.init)
    }

    func writeTargetAuditDiagnostics() throws -> [WriteTargetAuditDiagnostic] {
        try fetchWriteTargetAuditRecords().map(WriteTargetAuditDiagnostic.init)
    }
}
