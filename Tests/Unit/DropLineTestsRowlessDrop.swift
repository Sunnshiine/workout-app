import Testing

@testable import WorkoutTracker

private let twoDrops = [
    "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "F16": "8", "H16": "Drop 20%", "F17": "8", "H17": "Drop 30%",
    "C18": "Next Lift", "D18": "2", "F18": "10", "H18": "RPE8"
]
private let oneDrop = [
    "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "F16": "8", "H16": "Drop 20%",
    "C22": "Next Lift", "D22": "2", "F22": "10", "H22": "RPE8"
]
private let topSetLogged = ["I15": "8", "K15": "175x6@8"]
private let mainSets = ["e0.s0 RPE8 logged 175x6@8", "e1.s0 RPE8 pending ", "e1.s1 RPE8 pending "]

private func with(_ cells: [String: String], _ change: [String: String]) -> [String: String] {
    cells.merging(change) { _, new in new }.filter { !$0.value.isEmpty }
}

/// Verifier 6's V3a and V3 and the spill cases V6, V7, V7c and C19: the athlete queues a Drop's log,
/// and the coach then takes its row with a Coach Note, a hide, or a cleared Load. The log is refused
/// and kept on the phone. It never lands on another Drop's row, and never on a row the app no longer
/// reads. Each `mainCells` is what main's `workout` CLI left after the same steps without the Drop log,
/// which main could not queue.
private let workbooks = [
    DropWorkbook(
        testDescription: "V3a the first Drop queued, then its row taken",
        cells: twoDrops,
        hidden: [],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .log("w1d1.e0.s1", "140x8@9"), .edit(["K16": "Slow eccentric"]), .flush, .sync],
        mainCells: with(twoDrops, topSetLogged.merging(["K16": "Slow eccentric"]) { _, new in new }),
        mainSets: mainSets
    ),
    DropWorkbook(
        testDescription: "V3 both Drops queued, then the first one's row taken",
        cells: twoDrops,
        hidden: [],
        steps: [
            .log("w1d1.e0.s0", "175x6@8"), .log("w1d1.e0.s1", "140x8@9"), .log("w1d1.e0.s2", "122.5x8@9.5"),
            .edit(["K16": "Slow eccentric"]), .flush, .sync
        ],
        mainCells: with(twoDrops, topSetLogged.merging(["K16": "Slow eccentric"]) { _, new in new }),
        mainSets: mainSets
    ),
    DropWorkbook(
        testDescription: "V6 the coach hides the Drop's row",
        cells: oneDrop,
        hidden: [],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .log("w1d1.e0.s1", "140x8@9"), .hide([16]), .flush, .sync],
        mainCells: with(oneDrop, topSetLogged),
        mainSets: mainSets
    ),
    DropWorkbook(
        testDescription: "V7 the coach clears the Drop's Load",
        cells: oneDrop,
        hidden: [],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .log("w1d1.e0.s1", "140x8@9"), .edit(["F16": "", "H16": ""]), .flush, .sync],
        mainCells: with(oneDrop, topSetLogged.merging(["F16": "", "H16": ""]) { _, new in new }),
        mainSets: mainSets
    ),
    DropWorkbook(
        testDescription: "V7c three compact top Sets; the coach clears the Drop's Load",
        cells: with(oneDrop, ["D15": "3"]),
        hidden: [],
        steps: [
            .log("w1d1.e0.s0", "175x6@8"), .log("w1d1.e0.s2", "175x6@9"), .log("w1d1.e0.s3", "140x8@9"),
            .edit(["F16": "", "H16": ""]), .flush, .sync
        ],
        mainCells: with(oneDrop, ["D15": "3", "I15": "9", "K15": "175x6@8, , 175x6@9", "F16": "", "H16": ""]),
        mainSets: [
            "e0.s0 RPE8 logged 175x6@8", "e0.s1 RPE8 pending ", "e0.s2 RPE8 logged 175x6@9", "e1.s0 RPE8 pending ",
            "e1.s1 RPE8 pending "
        ]
    ),
    DropWorkbook(
        testDescription: "C19 the coach adds a Drop row, then removes it with its log queued",
        cells: with(oneDrop, ["F16": "", "H16": ""]),
        hidden: [],
        steps: [
            .log("w1d1.e0.s0", "175x6@8"), .flush, .edit(["F16": "8", "H16": "Drop 20%"]), .sync,
            .log("w1d1.e0.s1", "140x8@9"), .edit(["F16": "", "H16": ""]), .flush, .sync
        ],
        mainCells: with(oneDrop, topSetLogged.merging(["F16": "", "H16": ""]) { _, new in new }),
        mainSets: mainSets
    )
]

@MainActor
@Test("A Drop's queued log is refused when the coach takes its row", arguments: workbooks)
func aDropsQueuedLogIsRefusedWhenTheCoachTakesItsRow(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(replay.sets == workbook.mainSets)
    #expect(replay.queuedWrites > 0)
}
