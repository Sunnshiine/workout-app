@testable import WorkoutTracker

func gridFromA1(_ cells: [String: String], rows: Int, cols: Int) -> SheetGrid {
    var g = SheetGrid(repeating: [String](repeating: "", count: cols), count: rows)
    for (a1, value) in cells {
        let (r, c) = a1ToIndex(a1)
        if r < rows, c < cols { g[r][c] = value }
    }
    return g
}
