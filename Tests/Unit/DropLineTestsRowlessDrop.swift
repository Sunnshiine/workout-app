import Testing

@testable import WorkoutTracker

private let twoDrops = [
    "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "F16": "8", "H16": "Drop 20%", "F17": "8", "H17": "Drop 30%",
    "C18": "Next Lift", "D18": "2", "F18": "10", "H18": "RPE8"
]
private let mainCells = twoDrops.merging(["I15": "8", "K15": "175x6@8", "K16": "Slow eccentric"]) { _, new in new }

/// Verifier 6's V3a: the athlete logs the first Drop, and the coach then types a Coach Note on its
/// row, so it has no row left. The second Drop must not take the first one's Set index, or the
/// queued log would land in the second Drop's row as its own.
private let workbooks = [
    DropWorkbook(
        testDescription: "V3a the first Drop queued, then its row taken",
        cells: twoDrops,
        hidden: [],
        steps: [.log("w1d1.e0.s0", "175x6@8"), .log("w1d1.e0.s1", "140x8@9"), .edit(["K16": "Slow eccentric"]), .flush, .sync],
        mainCells: mainCells,
        mainSets: ["e0.s0 RPE8 logged 175x6@8", "e1.s0 RPE8 pending ", "e1.s1 RPE8 pending "]
    )
]

@MainActor
@Test("A Drop that loses its row hands its Set index to no other Drop", arguments: workbooks)
func aDropThatLosesItsRowHandsItsSetIndexToNoOtherDrop(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(replay.sets == workbook.mainSets)
}

/// V3: both Drops queued. The first one's log is refused. The second Drop is no longer read, so its
/// queued log takes main's path for an extra Set past the prescribed count: the Nth visible row
/// under the top Set, here its own row. A looser layout puts it on a spare row instead (#1247).
@MainActor
@Test func aDropThatLosesItsRowLeavesTheNextDropsLogOnItsOwnRow() async throws {
    let replay = try await replayed(
        DropWorkbook(
            testDescription: "V3",
            cells: twoDrops,
            hidden: [],
            steps: [
                .log("w1d1.e0.s0", "175x6@8"), .log("w1d1.e0.s1", "140x8@9"), .log("w1d1.e0.s2", "122.5x8@9.5"),
                .edit(["K16": "Slow eccentric"]), .flush, .sync
            ],
            mainCells: [:],
            mainSets: []
        )
    )
    #expect(replay.cells == mainCells.merging(["K17": "122.5x8@9.5"]) { _, new in new })
    #expect(replay.sets == ["e0.s0 RPE8 logged 175x6@8", "e1.s0 RPE8 pending ", "e1.s1 RPE8 pending "])
}
