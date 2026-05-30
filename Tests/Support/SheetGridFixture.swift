@testable import WorkoutTracker

func gridFromA1(_ cells: [String: String], rows: Int, cols: Int) -> SheetGrid {
    var g = SheetGrid(repeating: [String](repeating: "", count: cols), count: rows)
    for (a1, value) in cells {
        let (r, c) = a1ToIndex(a1)
        if r < rows, c < cols { g[r][c] = value }
    }
    return g
}

/// Day 1/2 week with a two-set exercise ("Chest Fly") whose header Notes cell holds a
/// protected coach note, followed by two logged continuation-row set logs, then a
/// single-set "Bench Press". Notes at column K (10). Row layout: week header at row 12,
/// role headers at row 14, "Chest Fly" anchor at row 18, "Bench Press" anchor at row 25.
func coachNoteLayoutGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "K14": "Notes",
            "C18": "Chest Fly", "D18": "2", "K18": "Keep elbows soft",
            "K19": "25x12@7",
            "K20": "20x10@8",
            "C25": "Bench Press", "D25": "1"
        ],
        rows: 32,
        cols: 30
    )
}
