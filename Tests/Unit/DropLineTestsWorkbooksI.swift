import Testing

@testable import WorkoutTracker

/// Verifier 4's I workbooks for #1245, each with the body cells main's `workout` CLI left after
/// the same steps. A Drop line the app now reads must leave every cell as main did, and read every
/// Set main read the same way, at the same address.
private let workbooks: [DropWorkbook] = [
    DropWorkbook(
        testDescription: "I1 coach edit: back-off Set queued, the coach types a Drop on the blank row above it",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "D17": "1", "F17": "8", "H17": "RPE7",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [
            .log("w1d1.e0.s1", "150x8@7"),
            .edit([
                "F16": "8", "H16": "Drop 20%"
            ]),
            .flush
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "7", "F16": "8", "H16": "Drop 20%",
            "D17": "1", "F17": "8", "H17": "RPE7", "K17": "150x8@7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e0.s1 RPE7 logged 150x8@7",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "I2 update: back-off Set queued on main below an uncounted Drop line",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "F16": "8", "H16": "Drop 20%", "D17": "1",
            "F17": "8", "H17": "RPE7", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.log("w1d1.e0.s1", "150x8@7"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "7", "F16": "8", "H16": "Drop 20%",
            "D17": "1", "F17": "8", "H17": "RPE7", "K17": "150x8@7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e0.s1 RPE7 logged 150x8@7",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "I3 coach edit: back-off Set queued, the coach types a named Drop row on the blank row above it",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "D17": "1", "F17": "8", "H17": "RPE7",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [
            .log("w1d1.e0.s1", "150x8@7"),
            .edit([
                "C16": "Drop", "F16": "8", "H16": "Drop 20%"
            ]),
            .flush,
            .sync
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "D17": "1", "F17": "8", "H17": "RPE7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e1.s0 Drop 20% pending ",
            "e1.s1 RPE7 pending ",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "I4 coach edit: third top Set queued (logs on rows below), the coach names a Drop row inside the span",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "D16": "1", "F16": "6", "H16": "RPE8",
            "D17": "1", "F17": "6", "H17": "RPE8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [
            .log("w1d1.e0.s2", "175x6@9"),
            .edit([
                "C16": "Drop", "H16": "Drop 20%"
            ]),
            .flush,
            .sync
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "D16": "1", "F16": "6",
            "H16": "Drop 20%", "D17": "1", "F17": "6", "H17": "RPE8", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e1.s0 Drop 20% pending ",
            "e1.s1 RPE8 pending ",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "I5 coach edit: Drop Set queued on its own row, the coach types a Coach Note there",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "F16": "8",
            "H16": "Drop 20%", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [
            .edit([
                "K16": "Slow eccentric"
            ]), .flush
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "F16": "8",
            "H16": "Drop 20%", "K16": "Slow eccentric", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "I6 coach edit: Drop Set queued, the coach hides its row",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "F16": "8",
            "H16": "Drop 20%", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.hide([16]), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "F16": "8",
            "H16": "Drop 20%", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "I7 coach edit: two Drops queued, the coach puts a Coach Note on the top Set",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "175x6@8", "F16": "8",
            "H16": "Drop 20%", "F17": "8", "H17": "Drop 30%", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        hidden: [],
        steps: [
            .edit([
                "K15": "Brace"
            ]), .flush
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "F16": "8",
            "H16": "Drop 20%", "F17": "8", "H17": "Drop 30%", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "I8 coach edit: back-off queued below a named Drop row, the coach renames the Drop row away",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "D17": "1", "F17": "8", "H17": "RPE7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [
            .log("w1d1.e1.s1", "150x8@7"),
            .edit([
                "C16": ""
            ]),
            .flush,
            .sync
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "F16": "8", "H16": "Drop 20%", "D17": "1",
            "F17": "8", "H17": "RPE7", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e0.s1 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "I9 coach edit: top Set queued, the coach unhides a row above the Drop rows",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "F17": "8",
            "H17": "Drop 20%", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [16],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .unhide([16]), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "Brace",
            "K16": "175x6@8", "F17": "8", "H17": "Drop 20%", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    )
]

@MainActor
@Test("Drop workbook I leaves main's cells", arguments: workbooks)
func dropWorkbookILeavesMainsCells(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(workbook.mainSets.filter { !replay.sets.contains($0) } == [])
}
