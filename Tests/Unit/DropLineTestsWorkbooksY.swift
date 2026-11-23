import Testing

@testable import WorkoutTracker

/// Verifier 4's Y workbooks for #1245, each with the body cells main's `workout` CLI left after
/// the same steps. A Drop line the app now reads must leave every cell as main did, and read every
/// Set main read the same way, at the same address.
private let workbooks: [DropWorkbook] = [
    DropWorkbook(
        testDescription: "Y1 update: named Drop row with a Coach Note, an uncounted Drop line right below it holds its "
            + "log on main, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "Slow", "F17": "8",
            "H17": "Drop 30%", "K17": "140x8@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync, .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8",
            "C16": "HB SQ Drop", "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "Slow", "F17": "8",
            "H17": "Drop 30%", "K17": "140x8@8", "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "Y1n as Y1 with the row named `Drop` and a counted Drop line too, seeded after main flushed",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8", "C16": "Drop",
            "D16": "1", "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "Slow", "D17": "1", "F17": "8",
            "H17": "Drop 30%", "K17": "122.5x8@8", "F18": "8", "H18": "Drop 40%", "K18": "140x8@8",
            "C19": "Bench", "D19": "1", "F19": "6", "H19": "RPE8", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        hidden: [],
        steps: [.sync],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8", "C16": "Drop",
            "D16": "1", "F16": "8", "H16": "Drop 20%", "I16": "8", "K16": "Slow", "D17": "1", "F17": "8",
            "H17": "Drop 30%", "K17": "122.5x8@8", "F18": "8", "H18": "Drop 40%", "K18": "140x8@8",
            "C19": "Bench", "D19": "1", "F19": "6", "H19": "RPE8", "C22": "Next Lift", "D22": "2", "F22": "10",
            "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 Drop 20% logged 140x8@8",
            "e1.s1 Drop 30% logged 122.5x8@8",
            "e2.s0 RPE8 pending ",
            "e3.s0 RPE8 pending ",
            "e3.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "Y1q update: as Y1 with main's write still queued",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "HB SQ Drop", "F16": "8",
            "H16": "Drop 20%", "K16": "Slow", "F17": "8", "H17": "Drop 30%", "C22": "Next Lift", "D22": "2",
            "F22": "10", "H22": "RPE8"
        ],
        hidden: [],
        steps: [.log("w1d1.e1.s0", "140x8@8"), .flush],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "C16": "HB SQ Drop", "F16": "8",
            "H16": "Drop 20%", "I16": "8", "K16": "Slow", "F17": "8", "H17": "Drop 30%", "K17": "140x8@8",
            "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 pending ",
            "e1.s0 Drop 20% logged 140x8@8",
            "e2.s0 RPE8 pending ",
            "e2.s1 RPE8 pending "
        ]
    )
]

@MainActor
@Test("Drop workbook Y leaves main's cells", arguments: workbooks)
func dropWorkbookYLeavesMainsCells(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(workbook.mainSets.filter { !replay.sets.contains($0) } == [])
}
