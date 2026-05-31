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

/// Day 1/2 week with a two-set Incline DB Bench Press whose header Notes cell
/// holds a protected AMRAP Coach Note. Set Logs must land on continuation rows,
/// and Last Set RPE must land on the exercise anchor row.
func coachNoteBenchPressRoundTripGrid() -> SheetGrid {
    gridFromA1(
        [
            "C37": "Day 1", "S37": "Day 2",
            "D39": "Sets", "F39": "Reps", "H39": "Load", "I39": "Last set RPE", "K39": "Notes",
            "C51": "2-3:1:0 Incline DB BP", "D51": "2", "F51": "7 - 8", "H51": "RPE8, RF",
            "K51": "AMRAP w/ 0:3:0 BW Push Up",
            "C55": "0:2:0 Hamstring Curl", "D55": "2"
        ],
        rows: 60,
        cols: 30
    )
}

/// Repeated Week sections with Coach Notes, hidden continuation rows, and
/// visible writable rows inside Week 2 / Day 1. The non-last Exercise must skip
/// row 42 and write to row 43. The last Exercise must skip row 47 and stay
/// inside the Session boundary before the next Week section at row 60.
func visibleWritableRowRoundTripSnapshot() -> SheetSnapshot {
    SheetSnapshot(
        values: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
                "C16": "Paused Squat", "D16": "1", "F16": "5", "H16": "RPE7",

                "C37": "Day 1", "S37": "Day 2",
                "D39": "Sets", "F39": "Reps", "H39": "Load", "I39": "Last set RPE", "K39": "Notes",
                "C41": "2-3:1:0 Incline DB BP", "D41": "2", "F41": "7 - 8", "H41": "RPE8, RF",
                "K41": "AMRAP w/ 0:3:0 BW Push Up",
                "K42": "999x1@10",
                "C46": "0:2:0 Hamstring Curl", "D46": "1", "F46": "12", "H46": "RPE8",
                "K46": "Controlled eccentric",
                "K47": "100x1@10",

                "C60": "Day 1", "S60": "Day 2",
                "D62": "Sets", "F62": "Reps", "H62": "Load", "I62": "Last set RPE", "K62": "Notes",
                "C64": "Bench Press", "D64": "1"
            ],
            rows: 70,
            cols: 30
        ),
        rowVisibility: [
            41: SheetRowVisibility(hiddenByUser: true),
            46: SheetRowVisibility(hiddenByFilter: true)
        ]
    )
}
