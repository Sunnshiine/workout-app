@testable import WorkoutTracker

extension SheetCellWrite {
    /// The write that lands `value` at `a1` on `tabName`, spelled the way the Sheet shows the cell
    /// ("K15" is row 14, column 10), so a recorded write reads like the cell it targets.
    init(tabName: String, a1: String, value: String) {
        let target = SheetWriteTarget(tabName: tabName, a1: a1)
        self.init(tabName: tabName, row: target.row, col: target.col, value: value)
    }
}

extension SheetWriteTarget {
    /// The target at `a1` on `tabName`, spelled the way the Sheet shows the cell.
    init(tabName: String, a1: String) {
        let index = a1CellIndex(a1)!
        self.init(tabName: tabName, row: index.row, col: index.col)
    }
}
