import Foundation

/// How one Set-Log placement decision reads to a developer in the Write Target Audit Log: the rows
/// the addressing rule scanned, what landing on a row means, and why no row was selected when the
/// scan came up empty. Each `SetLogPlacementKind` and each unresolved `SetLogPlacementResolution`
/// names its own narration here, beside the decision, so a new placement rule cannot ship with a
/// stale audit story.
struct SetLogPlacementNarration: Sendable, Equatable {
    /// The rows the rule scanned, narrated as skipped when hidden.
    let scannedRows: [Int]
    /// What the selected row is, as the clause after "Selected row N: ".
    let selection: String
    /// Why no row was selected, as the clause after "No row selected: ".
    let absence: String

    func text(selectedRow: Int?, in snapshot: SheetSnapshot) -> String {
        let prefix = hiddenRowsPrefix(in: snapshot)
        if let selectedRow {
            return "\(prefix)Selected row \(selectedRow + 1): \(selection)"
        }
        return "\(prefix)No row selected: \(absence)"
    }

    private func hiddenRowsPrefix(in snapshot: SheetSnapshot) -> String {
        let hidden = scannedRows.compactMap { row -> String? in
            guard let visibility = snapshot.rowVisibility[row], !visibility.isVisible else { return nil }
            return "row \(row + 1) \(Self.hiddenReason(visibility))"
        }
        guard !hidden.isEmpty else { return "" }
        return "Skipped hidden rows: \(hidden.joined(separator: ", ")). "
    }

    private static func hiddenReason(_ visibility: SheetRowVisibility) -> String {
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

extension SetLogPlacementNarration {
    static func multiLinePrescriptionLine(row: Int, listPosition: Int?) -> Self {
        Self(
            scannedRows: [row],
            selection: """
                Prescription Line row stores this Line's Set logs as a comma-separated list \
                (Set \((listPosition ?? 0) + 1) of the Line).
                """,
            absence: "Prescription Line row \(row + 1) is hidden."
        )
    }

    static func compactHeaderList(anchor: SheetLayoutExerciseAnchor) -> Self {
        Self(
            scannedRows: [anchor.row],
            selection: "compact header Notes row stores Set logs as a comma-separated list.",
            absence: "compact header Notes row \(anchor.row + 1) is hidden."
        )
    }

    static func protectedHeaderVisibleWritableRow(anchor: SheetLayoutExerciseAnchor) -> Self {
        Self(
            scannedRows: Array(anchor.row + 1..<anchor.nextAnchorRow),
            selection: "first visible writable row below protected header Notes before the next Exercise.",
            absence: "no visible writable row below protected header Notes before the next Exercise."
        )
    }

    /// The per-Set-row scan always starts below the anchor: a compact header keeps Set logs on the
    /// anchor row under its own placement kind, so this narration never claims the anchor row.
    static func visibleSetLogRow(setIndex: Int, anchor: SheetLayoutExerciseAnchor) -> Self {
        Self(
            scannedRows: Array(anchor.row + 1..<anchor.nextAnchorRow),
            selection: "visible Set row for Set \(setIndex + 1).",
            absence: "no visible Set row found for Set \(setIndex + 1) before the next Exercise."
        )
    }

    /// Last Set RPE is not resolved by the Set-Log addressing tree; it stays on the Exercise anchor
    /// row (ADR-0003), and its scan says so.
    static func lastSetRPE(anchor: SheetLayoutExerciseAnchor) -> Self {
        Self(
            scannedRows: [anchor.row],
            selection: "visible Exercise row for Last Set RPE.",
            absence: "Exercise row \(anchor.row + 1) is hidden."
        )
    }
}

extension SetLogPlacement {
    /// The audit story for this resolved placement: one narration per `SetLogPlacementKind`, so a
    /// new addressing rule cannot ship without one.
    func rowScanNarration(setIndex: Int, anchor: SheetLayoutExerciseAnchor) -> SetLogPlacementNarration {
        switch kind {
        case .multiLinePrescriptionLine:
            .multiLinePrescriptionLine(row: row, listPosition: listPosition)
        case .compactHeaderList:
            .compactHeaderList(anchor: anchor)
        case .protectedHeaderVisibleWritableRow:
            .protectedHeaderVisibleWritableRow(anchor: anchor)
        case .visibleSetLogRow:
            .visibleSetLogRow(setIndex: setIndex, anchor: anchor)
        }
    }
}

extension SetLogPlacementResolution {
    /// The audit story for this placement decision. An unresolved outcome narrates the scan that
    /// failed, so "where would it have gone?" and "why did nothing get selected?" share one answer.
    func rowScanNarration(setIndex: Int, anchor: SheetLayoutExerciseAnchor) -> SetLogPlacementNarration {
        switch self {
        case .placed(let placement):
            placement.rowScanNarration(setIndex: setIndex, anchor: anchor)
        case .protectedHeaderBlocksSetRow:
            .protectedHeaderVisibleWritableRow(anchor: anchor)
        case .setRowNotFound, .notesColumnMissing:
            .visibleSetLogRow(setIndex: setIndex, anchor: anchor)
        }
    }
}
