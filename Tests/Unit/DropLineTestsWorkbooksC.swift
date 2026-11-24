import Testing

@testable import WorkoutTracker

/// Verifier 5's C workbooks for #1245, each with the body cells main's `workout` CLI left after
/// the same steps. A Drop line the app now reads must leave every cell as main did, and read every
/// Set main read the same way, at the same address.
private let workbooks: [DropWorkbook] = [
    DropWorkbook(
        testDescription: "C3 top Coach Note, Drop row right below, next Exercise right after: the Drop has no row",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "K15": "Brace", "F16": "8",
            "H16": "Drop 20%", "C17": "Next Lift", "D17": "2", "F17": "10", "H17": "RPE8"
        ],
        hidden: [],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .flush, .flush, .sync],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "Brace", "F16": "8",
            "H16": "Drop 20%", "K16": "175x6@8", "C17": "Next Lift", "D17": "2", "F17": "10", "H17": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "C4n Drop row holds a Coach Note, no free row",
        cells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "F16": "8", "H16": "Drop 20%",
            "K16": "Slow eccentric", "C17": "Next Lift", "D17": "2", "F17": "10", "H17": "RPE8"
        ],
        hidden: [],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .flush, .flush, .sync],
        mainCells: [
            "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "I15": "8", "K15": "175x6@8", "F16": "8",
            "H16": "Drop 20%", "K16": "Slow eccentric", "C17": "Next Lift", "D17": "2", "F17": "10",
            "H17": "RPE8"
        ],
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8",
            "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    )
]

@MainActor
@Test("Drop workbook C leaves main's cells", arguments: workbooks)
func dropWorkbookCLeavesMainsCells(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(workbook.mainSets.filter { !replay.sets.contains($0) } == [])
}
