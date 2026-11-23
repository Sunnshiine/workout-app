import Testing

@testable import WorkoutTracker

/// Verifier 4's S workbooks for #1245, each with the body cells main's `workout` CLI left after
/// the same steps. A Drop line the app now reads must leave every cell as main did, and read every
/// Set main read the same way, at the same address.
private let workbooks: [DropWorkbook] = [
    DropWorkbook(
        testDescription: "S5b update: two Drop lines with Coach Notes under a named Drop row, coach text on the first "
            + "spare row, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "D16": "1", "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "Slow",
            "K17": "Superset w/ curls", "D18": "1", "F18": "8", "H18": "Drop 30%", "K18": "Keep tight",
            "K19": "120x8@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "D16": "1", "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "Slow",
            "K17": "Superset w/ curls", "D18": "1", "F18": "8", "H18": "Drop 30%", "K18": "Keep tight",
            "K19": "120x8@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged Superset w/ curls",
            "e1.s1 Drop 30% logged 120x8@8",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "S5c update: counted Lines above the named Drop row with Coach Notes, coach text on a spare "
            + "row, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "7", "K15": "Brace", "D16": "1",
            "F16": "8", "H16": "RPE7", "K16": "Tempo", "K17": "175x6@8", "K18": "150x8@7", "F19": "8",
            "H19": "Drop 20%", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "7", "K15": "Brace", "D16": "1",
            "F16": "8", "H16": "RPE7", "K16": "Tempo", "K17": "175x6@8", "K18": "150x8@7", "F19": "8",
            "H19": "Drop 20%", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e0.s1 RPE7 logged 150x8@7",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "S5d update: top Coach Note sends its log to the uncounted Drop row; next rows hold coach text "
            + "and a hidden row, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "Brace", "F16": "8",
            "H16": "Drop 20%", "K16": "175x6@8", "K17": "Superset w/ curls", "K18": "hidden text",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [18],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "Brace", "F16": "8",
            "H16": "Drop 20%", "K16": "175x6@8", "K17": "Superset w/ curls", "K18": "hidden text",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "S5e update: as S5d, no free row left (spares hold coach text or are hidden), seeded after main "
            + "flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "Brace", "F16": "8",
            "H16": "Drop 20%", "K16": "175x6@8", "K17": "Superset w/ curls", "K18": "hidden", "C19": "Bench",
            "D19": "1", "F19": "6", "H19": "RPE8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [18],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "Brace", "F16": "8",
            "H16": "Drop 20%", "K16": "175x6@8", "K17": "Superset w/ curls", "K18": "hidden", "C19": "Bench",
            "D19": "1", "F19": "6", "H19": "RPE8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    )
]

@MainActor
@Test("Drop workbook S leaves main's cells", arguments: workbooks)
func dropWorkbookSLeavesMainsCells(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(workbook.mainSets.filter { !replay.sets.contains($0) } == [])
}
