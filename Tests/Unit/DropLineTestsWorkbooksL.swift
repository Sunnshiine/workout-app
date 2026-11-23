import Testing

@testable import WorkoutTracker

/// Verifier 4's L workbooks for #1245, each with the body cells main's `workout` CLI left after
/// the same steps. A Drop line the app now reads must leave every cell as main did, and read every
/// Set main read the same way, at the same address.
private let workbooks: [DropWorkbook] = [
    DropWorkbook(
        testDescription: "L1 update: named Drop row with a Legacy Log, free row below, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "D16": "1", "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "140x8",
            "K17": "141x8@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .log("w1d1.e1.s0", "142x8@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "D16": "1", "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "140x8",
            "K17": "142x8@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged 142x8@8",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "L2 update: uncounted, unnamed Drop row with a Legacy Log; top Coach Note redirects to it on "
            + "main, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "Brace", "F16": "8",
            "H16": "Drop 20%", "K16": "175x6@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "Brace", "F16": "8",
            "H16": "Drop 20%", "K16": "175x6@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "L3 update: named Drop row, two Sets, Legacy Log, no free row, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "D16": "2", "F16": "8", "H16": "Drop 20%", "K16": "140x8, 140x8",
            "C17": "Bench", "D17": "1", "F17": "6", "H17": "RPE8", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "D16": "2", "F16": "8", "H16": "Drop 20%", "K16": "140x8, 140x8",
            "C17": "Bench", "D17": "1", "F17": "6", "H17": "RPE8", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged ",
            "e1.s1 Drop 20% logged ",
            "e2.s0 RPE8 pending ",
            "e3.s0 RPE8 pending ",
            "e3.s1 RPE8 pending "
        ]
    )
]

@MainActor
@Test("Drop workbook L leaves main's cells", arguments: workbooks)
func dropWorkbookLLeavesMainsCells(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(workbook.mainSets.filter { !replay.sets.contains($0) } == [])
}
