import Foundation

/// What one row's Sets, Reps and Load cells say about the Sets it prescribes.
struct PrescriptionRow: Sendable, Equatable {
    /// The most Sets one Prescription Line can prescribe. A larger count is a typo, and is read like
    /// a non-numeric one, so it cannot make sync build a Set per count (#686).
    private static let maxSetsPerLine = 99

    private let setsCell: String
    private let repsCell: String
    private let loadCell: String

    init(row: Int, in grid: SheetGrid, cols: DayColumns) {
        setsCell = grid.cellOrEmpty(row, cols.sets).trimmed
        repsCell = grid.cellOrEmpty(row, cols.reps).trimmed
        loadCell = grid.cellOrEmpty(row, cols.load)
    }

    /// The Sets cell's leading number, as `3` and `2 sets` give it, or nil. It is the count the app
    /// read on every row before it read Drop lines, so a row it gives a count to keeps that count,
    /// and its Sets keep their Set Logs.
    var setsCellCount: Int? {
        setsCell.first?.isNumber ?? false ? Self.capped(Int(setsCell.prefix { $0.isNumber })) : nil
    }

    /// The row's first Load value is a Drop.
    var isDrop: Bool {
        loadCell.contains("%") && PrescribedLoad(PrescriptionValueList.load(loadCell).value(at: 0)).isDrop
    }

    /// How many Sets this row adds as a continuation Line, or nil when it is not a Line. A Drop line
    /// is a Line however its count is written: its Sets cell's number, else `x2`, else the N of an
    /// `N x M` Reps cell, else one Set.
    var lineSetCount: Int? {
        if let setsCellCount { return setsCellCount }
        guard isDrop else { return nil }
        return timesCount ?? repsCell.wholeMatch(of: /(\d+)\s*[xX×]\s*\d.*/).flatMap { Self.capped(Int($0.1)) } ?? 1
    }

    /// `x2` in the Sets cell.
    private var timesCount: Int? {
        guard let first = setsCell.first, "xX×".contains(first) else { return nil }
        let rest = setsCell.dropFirst().trimmingCharacters(in: .whitespaces)
        return rest.allSatisfy(\.isNumber) ? Self.capped(Int(rest)) : nil
    }

    private static func capped(_ value: Int?) -> Int? {
        guard let value, value <= maxSetsPerLine else { return nil }
        return max(value, 1)
    }
}
