import Testing

@testable import WorkoutTracker

/// Verifier 4's R workbooks for #1245, each with the body cells main's `workout` CLI left after
/// the same steps. A Drop line the app now reads must leave every cell as main did, and read every
/// Set main read the same way, at the same address.
private let workbooks: [DropWorkbook] = [
    DropWorkbook(
        testDescription: "R1 update: write queued on the first `Drop` Exercise; a later `Drop` row does not merge (Load "
            + "-20lbs)",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "C18": "Bench", "D18": "1", "F18": "6", "H18": "RPE8", "C19": "Drop",
            "F19": "8", "H19": "-20lbs", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.log("w1d1.e1.s0", "140x8@8"), .flush, .sync],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "I16": "8", "K16": "140x8@8", "C18": "Bench", "D18": "1", "F18": "6",
            "H18": "RPE8", "C19": "Drop", "F19": "8", "H19": "-20lbs", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 RPE8 pending ",
            "e3.s0 -20lbs pending ",
            "e4.s0 RPE8 pending ",
            "e4.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "R1b as R1, the later `Drop` row's Load blank",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "C18": "Bench", "D18": "1", "F18": "6", "H18": "RPE8", "C19": "Drop",
            "F19": "8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.log("w1d1.e1.s0", "140x8@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "I16": "8", "K16": "140x8@8", "C18": "Bench", "D18": "1", "F18": "6",
            "H18": "RPE8", "C19": "Drop", "F19": "8", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 RPE8 pending ",
            "e3.s0  pending ",
            "e4.s0 RPE8 pending ",
            "e4.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "R2 update: write queued on the first `Drop` Exercise; the later `Drop` row sits under a hidden "
            + "named row",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "C18": "Bench", "D18": "1", "F18": "6", "H18": "RPE8", "C19": "Old Lift",
            "D19": "3", "F19": "8", "H19": "RPE7", "C20": "Drop", "F20": "8", "H20": "Drop 20%",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [19],
        steps: [.log("w1d1.e1.s0", "140x8@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "I16": "8", "K16": "140x8@8", "C18": "Bench", "D18": "1", "F18": "6",
            "H18": "RPE8", "C19": "Old Lift", "D19": "3", "F19": "8", "H19": "RPE7", "C20": "Drop", "F20": "8",
            "H20": "Drop 20%", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 RPE8 pending ",
            "e3.s0 Drop 20% pending ",
            "e4.s0 RPE8 pending ",
            "e4.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "R3 update: as R1 with HB SQ Drop twice, the second under a second HB SQ with an unread Load",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "HB SQ Drop", "F16": "8",
            "H16": "Drop 20%", "C18": "HB SQ", "D18": "1", "F18": "6", "H18": "RPE8", "C19": "HB SQ Drop",
            "F19": "8", "H19": "135", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.log("w1d1.e1.s0", "140x8@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "HB SQ Drop", "F16": "8",
            "H16": "Drop 20%", "I16": "8", "K16": "140x8@8", "C18": "HB SQ", "D18": "1", "F18": "6",
            "H18": "RPE8", "C19": "HB SQ Drop", "F19": "8", "H19": "135", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 RPE8 pending ",
            "e3.s0 135 pending ",
            "e4.s0 RPE8 pending ",
            "e4.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "R5 update: write queued on the later, unmerged `Drop` Exercise",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "C18": "Bench", "D18": "1", "F18": "6", "H18": "RPE8", "C19": "Drop",
            "F19": "8", "H19": "-20lbs", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.log("w1d1.e3.s0", "100x8@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "C18": "Bench", "D18": "1", "F18": "6", "H18": "RPE8", "C19": "Drop",
            "F19": "8", "H19": "-20lbs", "I19": "8", "K19": "100x8@8", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e1.s0 Drop 20% pending ",
            "e2.s0 RPE8 pending ",
            "e3.s0 -20lbs logged 100x8@8",
            "e4.s0 RPE8 pending ",
            "e4.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "R6 update: as R1, the later `Drop` already logged",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "C18": "Bench", "D18": "1", "F18": "6", "H18": "RPE8", "C19": "Drop",
            "F19": "8", "H19": "-20lbs", "I19": "8", "K19": "100x8@8", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.log("w1d1.e1.s0", "140x8@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "I16": "8", "K16": "140x8@8", "C18": "Bench", "D18": "1", "F18": "6",
            "H18": "RPE8", "C19": "Drop", "F19": "8", "H19": "-20lbs", "I19": "8", "K19": "100x8@8",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 RPE8 pending ",
            "e3.s0 -20lbs logged 100x8@8",
            "e4.s0 RPE8 pending ",
            "e4.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "R7 coach edit, no update: write queued on the first `Drop` (Load -20lbs); the coach rewrites "
            + "its Load as Drop 20%",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8", "H16": "-20lbs",
            "C18": "Bench", "D18": "1", "F18": "6", "H18": "RPE8", "C19": "Drop", "F19": "8", "H19": "-20lbs",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [
            .log("w1d1.e1.s0", "140x8@8"),
            .edit([
                "H16": "Drop 20%"
            ]),
            .flush,
            .sync
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Drop", "F16": "8",
            "H16": "Drop 20%", "I16": "8", "K16": "140x8@8", "C18": "Bench", "D18": "1", "F18": "6",
            "H18": "RPE8", "C19": "Drop", "F19": "8", "H19": "-20lbs", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 RPE8 pending ",
            "e3.s0 -20lbs pending ",
            "e4.s0 RPE8 pending ",
            "e4.s1 RPE8 pending "
        ]
    )
]

@MainActor
@Test("Drop workbook R leaves main's cells", arguments: workbooks)
func dropWorkbookRLeavesMainsCells(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(workbook.mainSets.filter { !replay.sets.contains($0) } == [])
}
