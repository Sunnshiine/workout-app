import Foundation

struct WeekSection {
    let headerRow: Int  // 0-based row holding "Day N"
    let roleHeaderRow: Int  // headerRow + 2
    let dateRow: Int  // headerRow + 1
    let dayStartCols: [Int]  // 0-based columns of Day 1..Day 4
}

private nonisolated(unsafe) let dayHeaderPattern = /^Day [1-4]$/

func locateWeekSections(in grid: SheetGrid) -> [WeekSection] {
    var byRow: [Int: [Int]] = [:]
    for r in 0..<grid.count {
        for c in 0..<grid[r].count where grid[r][c].wholeMatch(of: dayHeaderPattern) != nil {
            byRow[r, default: []].append(c)
        }
    }
    return byRow.keys.sorted().compactMap { row in
        let cols = byRow[row]!.sorted()
        guard !cols.isEmpty else { return nil }
        return WeekSection(headerRow: row, roleHeaderRow: row + 2, dateRow: row + 1, dayStartCols: cols)
    }
}
