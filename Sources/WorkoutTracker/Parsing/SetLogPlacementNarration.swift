import Foundation

enum SetLogPlacementNarration: Sendable, Equatable {
    case row(Int, selection: String)
    case scan(rows: [Int], selection: String, absence: String)

    func text(selectedRow: Int?, in snapshot: SheetSnapshot) -> String {
        switch self {
        case .row(let row, let selection):
            return "Selected row \((selectedRow ?? row) + 1): \(selection)"
        case .scan(let rows, let selection, let absence):
            let prefix = Self.hiddenRowsPrefix(rows, in: snapshot)
            if let selectedRow {
                return "\(prefix)Selected row \(selectedRow + 1): \(selection)"
            }
            return "\(prefix)No row selected: \(absence)"
        }
    }

    private static func hiddenRowsPrefix(_ rows: [Int], in snapshot: SheetSnapshot) -> String {
        let hidden = rows.compactMap { row -> String? in
            guard let visibility = snapshot.rowVisibility[row], !visibility.isVisible else { return nil }
            return "row \(row + 1) \(hiddenReason(visibility))"
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
        .row(
            row,
            selection: """
                Prescription Line row stores this Line's Set logs as a comma-separated list \
                (Set \((listPosition ?? 0) + 1) of the Line).
                """
        )
    }

    static func compactHeaderList(anchor: SheetLayoutExerciseAnchor) -> Self {
        .row(anchor.row, selection: "compact header Notes row stores Set logs as a comma-separated list.")
    }

    static func protectedHeaderVisibleWritableRow(anchor: SheetLayoutExerciseAnchor) -> Self {
        .scan(
            rows: Array(anchor.row + 1..<anchor.nextAnchorRow),
            selection: "first visible writable row below protected header Notes before the next Exercise.",
            absence: "no visible writable row below protected header Notes before the next Exercise."
        )
    }

    /// The per-Set-row scan always starts below the anchor: a compact header keeps Set logs on the
    /// anchor row under its own placement kind, so this narration never claims the anchor row.
    static func visibleSetLogRow(setIndex: Int, anchor: SheetLayoutExerciseAnchor) -> Self {
        .scan(
            rows: Array(anchor.row + 1..<anchor.nextAnchorRow),
            selection: "visible Set row for Set \(setIndex + 1).",
            absence: "no visible Set row found for Set \(setIndex + 1) before the next Exercise."
        )
    }

    static func lastSetRPE(anchor: SheetLayoutExerciseAnchor) -> Self {
        .row(anchor.row, selection: "visible Exercise row for Last Set RPE.")
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
