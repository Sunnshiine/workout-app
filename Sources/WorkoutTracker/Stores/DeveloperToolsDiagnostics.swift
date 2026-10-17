import Foundation

struct SheetWriteAuditDetails: Sendable, Equatable {
    let selectedA1Target: String?
    let rowScanDetails: String
    let currentValue: String?
    let valueCheckOutcome: String
}

extension SheetWriteAuditDetails {
    static func dayHeadersChangedMeaning(recorded: SessionAddress) -> SheetWriteAuditDetails {
        SheetWriteAuditDetails(
            selectedA1Target: nil,
            rowScanDetails: "No row selected: Week \(recorded.week), Day \(recorded.day) was queued by header rank, "
                + "and reading Day \(recorded.day) by rank and by header number does not give the same Session on this sheet.",
            currentValue: nil,
            valueCheckOutcome: "Not checked because no target was selected."
        )
    }
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
        let session = "Week \(request.session.address.week), Day \(request.session.address.day)"
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

/// Developer Tools' Current Session rows, and the one place a `CurrentSessionResolution` becomes
/// English: the CLI's `currentSessionReason` reads `reason` from here too.
struct CurrentSessionDebugInfo: Equatable, Sendable {
    let currentBlockTab: String
    let sheetDerivedSession: String
    let pinnedSession: String
    let viewedSession: String
    let resolvedCurrentSession: String
    let reason: String
    let localOnlyNote: String?
    /// Whether a Current Session Pin is stored for this Block, in force or not, for Reset to clear.
    let canClearPin: Bool

    var copyText: String {
        [
            "Current Session Debug Info",
            "Current Block Tab: \(currentBlockTab)",
            "Sheet-derived Session: \(sheetDerivedSession)",
            "Manual Current Session Override: \(pinnedSession)",
            "Displayed Session: \(viewedSession)",
            "Resolved Current Session: \(resolvedCurrentSession)",
            "Reason: \(reason)",
            localOnlyNote
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

extension CurrentSessionDebugInfo {
    /// `resolution` is nil while no Block is loaded.
    @MainActor
    init(resolution: CurrentSessionResolution?, viewedSession: Session?) {
        self.viewedSession = Self.label(for: viewedSession)
        guard let resolution else {
            currentBlockTab = "None"
            sheetDerivedSession = "None"
            pinnedSession = "None"
            resolvedCurrentSession = "None"
            reason = "No Block is loaded, so no Current Session is resolved."
            localOnlyNote = nil
            canClearPin = false
            return
        }

        currentBlockTab = resolution.blockTab
        sheetDerivedSession = Self.label(for: resolution.sheetDerivedSession)
        resolvedCurrentSession = Self.label(for: resolution.session)
        canClearPin = resolution.hasPin
        switch resolution.pin {
        case .unset:
            pinnedSession = "None"
            reason =
                resolution.sheetDerivedSession == nil
                ? "No Sheet-derived Session is available for this Block."
                : "No manual override is active, so Sheet-derived progress wins."
            localOnlyNote = nil
        case .inForce(let author):
            pinnedSession = "\(Self.label(for: resolution.session)) (\(Self.label(for: author)))"
            reason =
                switch author {
                case .moveOn: "Move On advanced to this Session, so it wins over Sheet-derived progress."
                case .madeCurrent: "The athlete made this Session current, so it wins over Sheet-derived progress."
                }
            localOnlyNote = "The Current Session Pin is local-only and is not Sheet data."
        case .noLongerResolves(let author):
            pinnedSession = "Saved pin no longer matches this Block (\(Self.label(for: author)))"
            reason = "The Current Session Pin no longer matches this Block, so Sheet-derived progress wins."
            localOnlyNote = nil
        case .unavailable(let session, let author):
            pinnedSession = "\(Self.label(for: session)), Unavailable (\(Self.label(for: author)))"
            reason = "The Current Session Pin names an Unavailable Session, so Sheet-derived progress wins."
            localOnlyNote = nil
        }
    }

    @MainActor
    private static func label(for session: Session?) -> String {
        guard let address = session?.address else { return "None" }
        return "Week \(address.week), Day \(address.day)"
    }

    private static func label(for author: CurrentSessionPin.Author) -> String {
        switch author {
        case .moveOn: "Move On"
        case .madeCurrent: "Make current"
        }
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
        block = write.recordedSession.blockTab
        week = "Week \(write.recordedSession.address.week)"
        day = "Day \(write.recordedSession.address.day)"
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
            entry.recordedSession.blockTab,
            "Week \(entry.recordedSession.address.week)",
            "Day \(entry.recordedSession.address.day)",
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
