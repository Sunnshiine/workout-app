import Testing

@testable import WorkoutTracker

/// Verifier 5's B workbooks for #1245, each with the body cells main's `workout` CLI left after
/// the same steps. A Drop line the app now reads must leave every cell as main did, and read every
/// Set main read the same way, at the same address.
private let workbooks: [DropWorkbook] = [
    DropWorkbook(
        testDescription: "B1 top Coach Note, hidden named row, visible counted line, no spare row above",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "C16": "Old Lift",
            "D16": "2", "F16": "8", "D17": "2", "F17": "8", "H17": "RPE7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        hidden: [16],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .flush, .sync],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "C16": "Old Lift",
            "D16": "2", "F16": "8", "D17": "2", "F17": "8", "H17": "RPE7", "K18": "175x6@8",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e0.s1 RPE7 pending ",
            "e0.s2 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "B5 blank anchor, hidden named row, visible counted line: log the top Set",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Old Lift", "D16": "2", "F16": "8",
            "D17": "2", "F17": "8", "H17": "RPE7", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [16],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "C16": "Old Lift",
            "D16": "2", "F16": "8", "D17": "2", "F17": "8", "H17": "RPE7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e0.s1 RPE7 pending ",
            "e0.s2 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "B6 top Legacy Log, hidden named row, visible counted line",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "3x6 175", "C16": "Old Lift",
            "D16": "2", "F16": "8", "D17": "2", "F17": "8", "H17": "RPE7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        hidden: [16],
        steps: [.sync, .log("w1d1.e0.s0", "175x6@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "3x6 175", "C16": "Old Lift",
            "D16": "2", "F16": "8", "D17": "2", "F17": "8", "H17": "RPE7", "K18": "175x6@8",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e0.s1 RPE7 pending ",
            "e0.s2 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "B7 top Coach Note, Drop row, hidden named row, visible counted line",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "F16": "8",
            "H16": "Drop 20%", "C17": "Old Lift", "D17": "2", "D18": "2", "F18": "8", "H18": "RPE7",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [17],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .flush, .flush, .sync],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "F16": "8",
            "H16": "Drop 20%", "K16": "175x6@8", "C17": "Old Lift", "D17": "2", "D18": "2", "F18": "8",
            "H18": "RPE7", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e0.s1 RPE7 pending ",
            "e0.s2 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "B8 3 top Sets with a Coach Note, hidden named row, visible counted line",
        cells: [
            "C15": "HB SQ", "D15": "3", "F15": "6", "H15": "RPE8", "K15": "Brace", "C16": "Old Lift",
            "D16": "2", "F16": "8", "D17": "2", "F17": "8", "H17": "RPE7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        hidden: [16],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .log("w1d1.e0.s2", "175x6@9"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "3", "F15": "6", "H15": "RPE8", "K15": "Brace", "C16": "Old Lift",
            "D16": "2", "F16": "8", "D17": "2", "F17": "8", "H17": "RPE7", "K18": "175x6@8, , 175x6@9",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e0.s1 RPE8 pending ",
            "e0.s2 RPE8 logged 175x6@9",
            "e0.s3 RPE7 pending ",
            "e0.s4 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "B9 as B1 with a blank visible row above the hidden named row",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "C17": "Old Lift",
            "D17": "2", "D18": "2", "F18": "8", "H18": "RPE7", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        hidden: [17],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .flush, .sync],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "K16": "175x6@8",
            "C17": "Old Lift", "D17": "2", "D18": "2", "F18": "8", "H18": "RPE7", "C22": "Next Lift",
            "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e0.s1 RPE7 pending ",
            "e0.s2 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    )
]

@MainActor
@Test("Drop workbook B leaves main's cells", arguments: workbooks)
func dropWorkbookBLeavesMainsCells(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(workbook.mainSets.filter { !replay.sets.contains($0) } == [])
}
