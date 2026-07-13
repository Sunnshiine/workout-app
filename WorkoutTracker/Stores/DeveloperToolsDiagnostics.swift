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
        guard
            request.column == .notes,
            let day = snapshot.layout.day(week: request.week, day: request.day),
            day.columns.notes == target.col,
            let anchor = day.exerciseAnchors.first(where: { $0.name == request.exerciseName })
        else { return actual }

        let lines = anchor.prescriptionLines(in: snapshot.grid, setsColumn: day.columns.sets)
        if lines.isMultiLine, let line = lines.line(containing: request.setIndex), line.row == target.row,
            let position = line.position(of: request.setIndex) {
            return SetLogList(cell: actual).token(at: position)
        }

        let headerNotes = anchor.headerNotes(in: snapshot.grid, notesColumn: day.columns.notes)
        let setCount = anchor.prescribedSetCount(in: snapshot.grid, setsColumn: day.columns.sets)
        let usesHeaderTarget =
            anchor.row == target.row
            && anchor.usesCompactHeaderSetOne(headerNotes: headerNotes, setCount: setCount)
        let usesVisibleWritableTarget =
            anchor.row != target.row
            && anchor.isHeaderProtectedFromSetLogWrites(headerNotes: headerNotes, setCount: setCount)
        guard setCount > 1, request.setIndex < setCount, usesHeaderTarget || usesVisibleWritableTarget else {
            return actual
        }

        return SetLogList(cell: actual).token(at: request.setIndex)
    }

    private func rowScanDetails(
        for request: SheetWriteRequest,
        selectedRow: Int?,
        in snapshot: SheetWritePlanningSnapshot
    ) -> String {
        guard let day = snapshot.layout.day(week: request.week, day: request.day) else {
            return "No row selected: Week \(request.week), Day \(request.day) was not found."
        }
        guard let anchor = day.exerciseAnchors.first(where: { $0.name == request.exerciseName }) else {
            return "No row selected: \(request.exerciseName) was not found in Week \(request.week), Day \(request.day)."
        }

        if request.column == .lastSetRPE {
            return lastSetRPERowScanDetails(anchor: anchor, selectedRow: selectedRow, in: snapshot.snapshot)
        }

        let lines = anchor.prescriptionLines(in: snapshot.grid, setsColumn: day.columns.sets)
        if lines.isMultiLine, let line = lines.line(containing: request.setIndex) {
            return multiLinePrescriptionRowScanDetails(
                line: line,
                setIndex: request.setIndex,
                selectedRow: selectedRow,
                in: snapshot.snapshot
            )
        }

        let headerNotes = anchor.headerNotes(in: snapshot.grid, notesColumn: day.columns.notes)
        let setCount = anchor.prescribedSetCount(in: snapshot.grid, setsColumn: day.columns.sets)
        let compactHeaderSetOne =
            anchor.usesCompactHeaderSetOne(headerNotes: headerNotes, setCount: setCount)

        if compactHeaderSetOne, request.setIndex < setCount {
            return compactHeaderRowScanDetails(anchor: anchor, selectedRow: selectedRow, in: snapshot.snapshot)
        }

        if anchor.isHeaderProtectedFromSetLogWrites(headerNotes: headerNotes, setCount: setCount),
            request.setIndex < setCount
        {
            return protectedHeaderRowScanDetails(anchor: anchor, selectedRow: selectedRow, in: snapshot.snapshot)
        }

        return visibleSetRowScanDetails(
            setIndex: request.setIndex,
            compactHeaderSetOne: compactHeaderSetOne,
            anchor: anchor,
            selectedRow: selectedRow,
            in: snapshot.snapshot
        )
    }

    private func lastSetRPERowScanDetails(
        anchor: SheetLayoutExerciseAnchor,
        selectedRow: Int?,
        in snapshot: SheetSnapshot
    ) -> String {
        let prefix = hiddenRowDescription([anchor.row], in: snapshot).map { "Skipped hidden rows: \($0). " } ?? ""
        if let selectedRow {
            return "\(prefix)Selected row \(selectedRow + 1): visible Exercise row for Last Set RPE."
        }
        return "\(prefix)No row selected: Exercise row \(anchor.row + 1) is hidden."
    }

    private func compactHeaderRowScanDetails(
        anchor: SheetLayoutExerciseAnchor,
        selectedRow: Int?,
        in snapshot: SheetSnapshot
    ) -> String {
        let prefix = hiddenRowDescription([anchor.row], in: snapshot).map { "Skipped hidden rows: \($0). " } ?? ""
        if let selectedRow {
            return "\(prefix)Selected row \(selectedRow + 1): compact header Notes row stores Set logs as a comma-separated list."
        }
        return "\(prefix)No row selected: compact header Notes row \(anchor.row + 1) is hidden."
    }

    private func multiLinePrescriptionRowScanDetails(
        line: PrescriptionLine,
        setIndex: Int,
        selectedRow: Int?,
        in snapshot: SheetSnapshot
    ) -> String {
        let prefix = hiddenRowDescription([line.row], in: snapshot).map { "Skipped hidden rows: \($0). " } ?? ""
        let position = (line.position(of: setIndex) ?? 0) + 1
        if let selectedRow {
            return """
                \(prefix)Selected row \(selectedRow + 1): Prescription Line row stores this Line's Set logs as a \
                comma-separated list (Set \(position) of the Line).
                """
        }
        return "\(prefix)No row selected: Prescription Line row \(line.row + 1) is hidden."
    }

    private func protectedHeaderRowScanDetails(
        anchor: SheetLayoutExerciseAnchor,
        selectedRow: Int?,
        in snapshot: SheetSnapshot
    ) -> String {
        let rows = anchor.row + 1..<anchor.nextAnchorRow
        let prefix = hiddenRowDescription(Array(rows), in: snapshot).map { "Skipped hidden rows: \($0). " } ?? ""
        if let selectedRow {
            return """
                \(prefix)Selected row \(selectedRow + 1): first visible writable row below protected header Notes \
                before the next Exercise.
                """
        }
        return "\(prefix)No row selected: no visible writable row below protected header Notes before the next Exercise."
    }

    private func visibleSetRowScanDetails(
        setIndex: Int,
        compactHeaderSetOne: Bool,
        anchor: SheetLayoutExerciseAnchor,
        selectedRow: Int?,
        in snapshot: SheetSnapshot
    ) -> String {
        let firstRow = anchor.row + (compactHeaderSetOne ? 0 : 1)
        let rows = firstRow..<anchor.nextAnchorRow
        let prefix = hiddenRowDescription(Array(rows), in: snapshot).map { "Skipped hidden rows: \($0). " } ?? ""
        if let selectedRow {
            return "\(prefix)Selected row \(selectedRow + 1): visible Set row for Set \(setIndex + 1)."
        }
        return "\(prefix)No row selected: no visible Set row found for Set \(setIndex + 1) before the next Exercise."
    }

    private func hiddenRowDescription(_ rows: [Int], in snapshot: SheetSnapshot) -> String? {
        let descriptions = rows.compactMap { row -> String? in
            guard let visibility = snapshot.rowVisibility[row], !visibility.isVisible else { return nil }
            return "row \(row + 1) \(hiddenReason(visibility))"
        }
        guard !descriptions.isEmpty else { return nil }
        return descriptions.joined(separator: ", ")
    }

    private func hiddenReason(_ visibility: SheetRowVisibility) -> String {
        switch (visibility.hiddenByUser, visibility.hiddenByFilter) {
        case (true, true):
            "hidden by user and filter"
        case (true, false):
            "hidden by user"
        case (false, true):
            "hidden by filter"
        case (false, false):
            "visible"
        }
    }

}

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
