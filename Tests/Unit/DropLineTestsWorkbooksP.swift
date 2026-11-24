import Testing

@testable import WorkoutTracker

/// Verifier 4's P workbooks for #1245, each with the body cells main's `workout` CLI left after
/// the same steps. A Drop line the app now reads must leave every cell as main did, and read every
/// Set main read the same way, at the same address.
private let workbooks: [DropWorkbook] = [
    DropWorkbook(
        testDescription: "P1 update: anchor Sets `1+2`, logged; an uncounted Drop below, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1+2", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8", "F16": "8",
            "H16": "Drop 20%", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1+2", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8", "F16": "8",
            "H16": "Drop 20%", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "P3 update: counted Drop Line with a Coach Note; its logs sit on a Drop row whose Sets cell is "
            + "`100`, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "9", "K15": "175x6@8", "D16": "2",
            "F16": "8", "H16": "Drop 20%", "K16": "Slow", "D17": "100", "F17": "8", "H17": "Drop 30%",
            "K17": "140x8@8, 140x8@9", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "9", "K15": "175x6@8", "D16": "2",
            "F16": "8", "H16": "Drop 20%", "K16": "Slow", "D17": "100", "F17": "8", "H17": "Drop 30%",
            "K17": "140x8@8, 140x8@9", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e0.s1 Drop 20% logged 140x8@8",
            "e0.s2 Drop 20% logged 140x8@9",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "P3q update: as P3 with main's writes still queued",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "D16": "2", "F16": "8", "H16": "Drop 20%",
            "K16": "Slow", "D17": "100", "F17": "8", "H17": "Drop 30%", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [
            .log("w1d1.e0.s0", "175x6@8"),
            .log("w1d1.e0.s1", "140x8@8"),
            .log("w1d1.e0.s2", "140x8@9"),
            .flush
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "9", "K15": "175x6@8", "D16": "2",
            "F16": "8", "H16": "Drop 20%", "K16": "Slow", "D17": "100", "F17": "8", "H17": "Drop 30%",
            "K17": "140x8@8, 140x8@9", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e0.s1 Drop 20% logged 140x8@8",
            "e0.s2 Drop 20% logged 140x8@9",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "P4 update: Line `1+2` with a Drop Load between two counted Lines, writes queued",
        cells: [
            "C15": "HB SQ", "D15": "2", "F15": "6", "H15": "RPE8", "D16": "1+2", "F16": "8", "H16": "Drop 20%",
            "D17": "x2", "F17": "8", "H17": "Drop 30%", "D18": "1", "F18": "10", "H18": "RPE6",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [
            .log("w1d1.e0.s1", "175x6@8"),
            .log("w1d1.e0.s2", "140x8@8"),
            .log("w1d1.e0.s3", "100x10@6"),
            .flush,
            .flush
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "2", "F15": "6", "H15": "RPE8", "I15": "6", "K15": ", 175x6@8",
            "D16": "1+2", "F16": "8", "H16": "Drop 20%", "K16": "140x8@8", "D17": "x2", "F17": "8",
            "H17": "Drop 30%", "D18": "1", "F18": "10", "H18": "RPE6", "K18": "100x10@6", "C22": "Next Lift",
            "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e0.s1 RPE8 logged 175x6@8",
            "e0.s2 Drop 20% logged 140x8@8",
            "e0.s3 RPE6 logged 100x10@6",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "P5 update: three top Sets with a Coach Note logged on an `x2` Drop row",
        cells: [
            "C15": "HB SQ", "D15": "3", "F15": "6", "H15": "RPE8", "K15": "Brace", "D16": "x2", "F16": "8",
            "H16": "Drop 20%", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [
            .log("w1d1.e0.s0", "175x6@8"),
            .log("w1d1.e0.s2", "175x6@9"),
            .flush,
            .sync,
            .log("w1d1.e0.s1", "175x6@8.5"),
            .flush
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "3", "F15": "6", "H15": "RPE8", "I15": "9", "K15": "Brace", "D16": "x2",
            "F16": "8", "H16": "Drop 20%", "K16": "175x6@8, 175x6@8.5, 175x6@9", "C22": "Next Lift",
            "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e0.s1 RPE8 logged 175x6@8.5",
            "e0.s2 RPE8 logged 175x6@9",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "P6 update: named Drop row `x2`, logged on main as one Set, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "D16": "x2", "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "140x8@8",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "D16": "x2", "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "140x8@8",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "P7 update: named Drop row, Reps `2 x 8`, Coach Note; main's log on the row below, seeded after "
            + "main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "F16": "2 x 8", "H16": "Drop 20%", "I16": "8", "K16": "Slow",
            "K17": "140x8@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "F16": "2 x 8", "H16": "Drop 20%", "I16": "8", "K16": "Slow",
            "K17": "140x8@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    )
]

@MainActor
@Test("Drop workbook P leaves main's cells", arguments: workbooks)
func dropWorkbookPLeavesMainsCells(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(workbook.mainSets.filter { !replay.sets.contains($0) } == [])
}
