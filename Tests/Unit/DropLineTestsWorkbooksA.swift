import Testing

@testable import WorkoutTracker

/// Verifier 5's A workbooks for #1245, each with the body cells main's `workout` CLI left after
/// the same steps. A Drop line the app now reads must leave every cell as main did, and read every
/// Set main read the same way, at the same address.
private let workbooks: [DropWorkbook] = [
    DropWorkbook(
        testDescription: "A1 update: main queues a log on a visible counted line under a hidden named row; head syncs "
            + "and flushes",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Old Lift", "D16": "2", "F16": "8",
            "D17": "2", "F17": "8", "H17": "RPE7", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [16],
        steps: [.log("w1d1.e0.s1", "150x8@7"), .sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Old Lift", "D16": "2", "F16": "8",
            "D17": "2", "F17": "8", "H17": "RPE7", "K17": "150x8@7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e0.s1 RPE7 logged 150x8@7",
            "e0.s2 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "A10 athlete clears a wrong log, flushes, then logs the Set again",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Old Lift", "D16": "2", "F16": "8",
            "D17": "2", "F17": "8", "H17": "RPE7", "K17": "150x8@7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        hidden: [16],
        steps: [
            .deleteLog("w1d1.e0.s1"),
            .flush,
            .log("w1d1.e0.s1", "155x8@7"),
            .flush,
            .sync
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Old Lift", "D16": "2", "F16": "8",
            "D17": "2", "F17": "8", "H17": "RPE7", "K17": "155x8@7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e0.s1 RPE7 logged 155x8@7",
            "e0.s2 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "A11 as A10 with a sync after the clear",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Old Lift", "D16": "2", "F16": "8",
            "D17": "2", "F17": "8", "H17": "RPE7", "K17": "150x8@7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        hidden: [16],
        steps: [
            .deleteLog("w1d1.e0.s1"),
            .flush,
            .sync,
            .log("w1d1.e0.s1", "155x8@7"),
            .flush,
            .sync
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Old Lift", "D16": "2", "F16": "8",
            "D17": "2", "F17": "8", "H17": "RPE7", "K17": "155x8@7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e0.s1 RPE7 logged 155x8@7",
            "e0.s2 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "A2 update: as A1 with an unnamed Drop row above the hidden row",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "F16": "8", "H16": "Drop 20%",
            "C17": "Old Lift", "D17": "2", "D18": "2", "F18": "8", "H18": "RPE7", "C22": "Next Lift",
            "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [17],
        steps: [.log("w1d1.e0.s1", "150x8@7"), .sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "F16": "8", "H16": "Drop 20%",
            "C17": "Old Lift", "D17": "2", "D18": "2", "F18": "8", "H18": "RPE7", "K18": "150x8@7",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e0.s1 RPE7 logged 150x8@7",
            "e0.s2 RPE7 pending ",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "A4 coach clears the line's Set Log between the athlete's log and the flush",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "Old Lift", "D16": "2", "F16": "8",
            "D17": "2", "F17": "8", "H17": "RPE7", "K17": "150x8@7", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        hidden: [16],
        steps: [
            .log("w1d1.e0.s2", "150x8@8"),
            .edit([
                "K17": ""
            ]),
            .flush,
            .sync
        ],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "C16": "Old Lift", "D16": "2",
            "F16": "8", "D17": "2", "F17": "8", "H17": "RPE7", "K17": ", 150x8@8", "C22": "Next Lift",
            "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e0.s1 RPE7 pending ",
            "e0.s2 RPE7 logged 150x8@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    )
]

@MainActor
@Test("Drop workbook A leaves main's cells", arguments: workbooks)
func dropWorkbookALeavesMainsCells(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(workbook.mainSets.filter { !replay.sets.contains($0) } == [])
}
