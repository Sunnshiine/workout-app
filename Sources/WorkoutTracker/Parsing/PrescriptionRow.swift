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

    /// The Sets cell's count: `3` and `2 sets`, and on a row whose Load lists a Drop, `x2` and
    /// `1+2` as 3. Nil when it names no count. A row with no Drop reads only the leading number, as
    /// the app read every row before it read Drop lines, so those Sets keep their Set Logs.
    var setsCellCount: Int? { Self.count(inSetsCell: setsCell, readsDropForms: listsADrop) }

    /// The Sets cell starts with a number, as `3` and `2 sets` do and `x2` does not.
    var setsCellStartsWithACount: Bool { setsCell.first?.isNumber ?? false }

    /// The row's first Load value is a Drop.
    var isDrop: Bool {
        loadCell.contains("%") && PrescribedLoad(PrescriptionValueList.load(loadCell).value(at: 0)).isDrop
    }

    private var listsADrop: Bool {
        loadCell.contains("%") && loadCell.split(separator: ",").contains { PrescribedLoad(String($0)).isDrop }
    }

    /// How many Sets this row adds as a continuation Line, or nil when it is not a Line. A Drop line
    /// is a Line however its count is written: its Sets cell, else the N of an `N x M` Reps cell,
    /// else one Set.
    var lineSetCount: Int? {
        if let setsCellCount { return setsCellCount }
        guard isDrop else { return nil }
        return repsCell.wholeMatch(of: /(\d+)\s*[xX×]\s*\d.*/).flatMap { Self.capped(Int($0.1)) } ?? 1
    }

    private static func count(inSetsCell text: String, readsDropForms: Bool) -> Int? {
        if readsDropForms, let count = dropFormCount(text) { return count }
        return text.first?.isNumber ?? false ? capped(Int(text.prefix { $0.isNumber })) : nil
    }

    /// `1+2` and `x2`.
    private static func dropFormCount(_ text: String) -> Int? {
        if let sum = sum(of: text) { return capped(sum) }
        guard let first = text.first, "xX×".contains(first) else { return nil }
        let rest = text.dropFirst().trimmingCharacters(in: .whitespaces)
        return rest.allSatisfy(\.isNumber) ? capped(Int(rest)) : nil
    }

    /// `1+2` as 3. Nil unless every side of a `+` is a whole number.
    private static func sum(of text: String) -> Int? {
        guard text.contains("+") else { return nil }
        let addends = text.split(separator: "+", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
        return addends.allSatisfy { $0 != nil } ? addends.compactMap { $0 }.reduce(0, +) : nil
    }

    private static func capped(_ value: Int?) -> Int? {
        guard let value, value <= maxSetsPerLine else { return nil }
        return max(value, 1)
    }
}
