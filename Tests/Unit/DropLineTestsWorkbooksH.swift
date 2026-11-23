import Testing

@testable import WorkoutTracker

/// Verifier 4's H workbooks for #1245, each with the body cells main's `workout` CLI left after
/// the same steps. A Drop line the app now reads must leave every cell as main did, and read every
/// Set main read the same way, at the same address.
private let workbooks: [DropWorkbook] = [
    DropWorkbook(
        testDescription: "H2 update: two named Drop rows with Coach Notes, hidden rows inside each span, seeded after "
            + "main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8", "C16": "Drop",
            "F16": "8", "H16": "Drop 20%", "K16": "Slow", "C18": "Drop", "F18": "8", "H18": "Drop 30%",
            "I18": "8", "K18": "Fast", "K20": "122.5x8@8", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        hidden: [17, 19],
        steps: [.sync, .log("w1d1.e1.s0", "140x8@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8", "C16": "Drop",
            "F16": "8", "H16": "Drop 20%", "K16": "Slow", "C18": "Drop", "F18": "8", "H18": "Drop 30%",
            "I18": "8", "K18": "Fast", "K20": "122.5x8@8", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 Drop 30% logged 122.5x8@8",
            "e3.s0 RPE8 pending ",
            "e3.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "H3 update: three named Drop rows, first and third with Coach Notes, second free, seeded after "
            + "main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8", "C16": "Drop",
            "F16": "8", "H16": "Drop 20%", "K16": "A", "C17": "Drop", "F17": "8", "H17": "Drop 30%",
            "I17": "8", "K17": "122.5x8@8", "C18": "Drop", "F18": "8", "H18": "Drop 40%", "I18": "8",
            "K18": "B", "K19": "105x8@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .log("w1d1.e1.s0", "140x8@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8", "C16": "Drop",
            "F16": "8", "H16": "Drop 20%", "K16": "A", "C17": "Drop", "F17": "8", "H17": "Drop 30%",
            "I17": "8", "K17": "122.5x8@8", "C18": "Drop", "F18": "8", "H18": "Drop 40%", "I18": "8",
            "K18": "B", "K19": "105x8@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 Drop 30% logged 122.5x8@8",
            "e3.s0 Drop 40% logged 105x8@8",
            "e4.s0 RPE8 pending ",
            "e4.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "H4 update: named Drop row with a counted non-Drop Line below it (a multi-line Exercise on "
            + "main), seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "D16": "1", "F16": "8", "H16": "Drop 20%", "I16": "6", "K16": "140x8@8",
            "D17": "2", "F17": "8", "H17": "RPE6", "K17": ", 130x8@6", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .log("w1d1.e1.s1", "131x8@6"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "D16": "1", "F16": "8", "H16": "Drop 20%", "I16": "6", "K16": "140x8@8",
            "D17": "2", "F17": "8", "H17": "RPE6", "K17": "131x8@6, 130x8@6", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged 140x8@8",
            "e1.s1 RPE6 logged 131x8@6",
            "e1.s2 RPE6 logged 130x8@6",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "H5 read: named Drop row, one Set, two hand-typed logs in its Notes, a counted Line below",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "C16": "HB SQ Drop",
            "D16": "1", "F16": "8", "H16": "Drop 20%", "K16": "140x8@8, 135x8@9", "D17": "1", "F17": "8",
            "H17": "RPE6", "K17": "130x8@6, 125x8@6", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .log("w1d1.e1.s0", "141x8@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "C16": "HB SQ Drop",
            "D16": "1", "F16": "8", "H16": "Drop 20%", "K16": "140x8@8, 135x8@9", "D17": "1", "F17": "8",
            "H17": "RPE6", "K17": "130x8@6, 125x8@6", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged 141x8@8",
            "e1.s1 RPE6 pending ",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "H5b named Drop row; a counted Line below it holds a Legacy Log; the athlete logs that Line's Set",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "C16": "HB SQ Drop",
            "D16": "1", "F16": "8", "H16": "Drop 20%", "K16": "", "D17": "1", "F17": "8", "H17": "RPE6",
            "K17": "130x8, 125x8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .log("w1d1.e1.s1", "131x8@6"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "C16": "HB SQ Drop",
            "D16": "1", "F16": "8", "H16": "Drop 20%", "D17": "1", "F17": "8", "H17": "RPE6",
            "K17": "130x8, 125x8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% pending ",
            "e1.s1 RPE6 logged 131x8@6",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "H5c uncounted unnamed Drop row holding a Legacy Log; the athlete logs the Drop",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "F16": "8",
            "H16": "Drop 20%", "K16": "140x8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "F16": "8",
            "H16": "Drop 20%", "K16": "140x8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "H6 update: named Drop row with a Coach Note, hidden named row below it, then a free row "
            + "(main's redirect), seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8", "C16": "Drop",
            "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "Slow", "C17": "Old Lift", "D17": "3",
            "F17": "8", "H17": "RPE7", "K18": "140x8@8", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        hidden: [17],
        steps: [.sync, .log("w1d1.e1.s0", "141x8@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8", "C16": "Drop",
            "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "Slow", "C17": "Old Lift", "D17": "3",
            "F17": "8", "H17": "RPE7", "K18": "141x8@8", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged 141x8@8",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "H7 update: top Coach Note, hidden named row, a counted old Line, then the free row main "
            + "redirects to, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "C16": "Old Lift",
            "D16": "3", "F16": "8", "H16": "RPE7", "D17": "3", "F17": "10", "H17": "RPE7", "K18": "175x6@8",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [16],
        steps: [.sync],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "C16": "Old Lift",
            "D16": "3", "F16": "8", "H16": "RPE7", "D17": "3", "F17": "10", "H17": "RPE7", "K18": "175x6@8",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e0.s1 RPE7 pending ",
            "e0.s2 RPE7 pending ",
            "e0.s3 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "H7b as H7, then the athlete logs the top Set again on the new build, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "C16": "Old Lift",
            "D16": "3", "F16": "8", "H16": "RPE7", "D17": "3", "F17": "10", "H17": "RPE7", "K18": "175x6@8",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [16],
        steps: [.sync, .log("w1d1.e0.s0", "176x6@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "C16": "Old Lift",
            "D16": "3", "F16": "8", "H16": "RPE7", "D17": "3", "F17": "10", "H17": "RPE7", "K18": "176x6@8",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 176x6@8",
            "e0.s1 RPE7 pending ",
            "e0.s2 RPE7 pending ",
            "e0.s3 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "H8 update: uncounted Drop under a hidden blank row and above a hidden row; top Coach Note, "
            + "seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "Brace", "F17": "8",
            "H17": "Drop 20%", "K17": "175x6@8", "K20": "Coach: deload next week", "C22": "Next Lift",
            "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [16, 18],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "Brace", "F17": "8",
            "H17": "Drop 20%", "K17": "175x6@8", "K20": "Coach: deload next week", "C22": "Next Lift",
            "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    )
]

@MainActor
@Test("Drop workbook H leaves main's cells", arguments: workbooks)
func dropWorkbookHLeavesMainsCells(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(workbook.mainSets.filter { !replay.sets.contains($0) } == [])
}
