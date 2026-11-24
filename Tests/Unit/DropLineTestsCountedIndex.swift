import Testing

@testable import WorkoutTracker

private let topSetAndLine: [String: String] = [
    "C15": "HB SQ", "D15": "2", "F15": "6", "H15": "RPE8", "D16": "1", "F16": "8", "H16": "RPE7",
    "F17": "8", "H17": "Drop 20%", "C18": "Next Lift", "D18": "2", "F18": "10", "H18": "RPE8"
]

private let threeLines: [String: String] = [
    "C15": "HB SQ", "D15": "1", "F15": "6", "H15": "RPE8", "D16": "1", "F16": "8", "H16": "RPE7",
    "D17": "1", "F17": "8", "H17": "RPE6", "F18": "8", "H18": "Drop 20%",
    "C19": "Next Lift", "D19": "2", "F19": "10", "H19": "RPE8"
]

private let twoDrops: [String: String] = [
    "C15": "HB SQ", "D15": "3", "F15": "6", "H15": "RPE8", "D16": "1", "F16": "8", "H16": "RPE7",
    "F17": "8", "H17": "Drop 20%", "F18": "8", "H18": "Drop 30%",
    "C19": "Next Lift", "D19": "2", "F19": "10", "H19": "RPE8"
]

private let painInHip = SetFlag(kind: .pain, text: "hip")!

private func lowered(_ cells: [String: String], _ edit: [String: String]) -> [String: String] {
    cells.merging(edit) { _, new in new }.filter { !$0.value.isEmpty }
}

/// Verifier 7's R1 workbooks: a counted Line's write is queued, then the coach changes the counted
/// Sets above it, so an added Drop below now has the write's Set index. Main refuses each write, as
/// no counted Set has that index any more. The write must not land on the Drop's row, and the Drop
/// must not read it as its own. Each `mainCells` is what main's `workout` CLI left; main reads
/// every counted Set Pending.
private let workbooks: [DropWorkbook] = [
    DropWorkbook(
        testDescription: "R1 the coach lowers the top Set's count with Set 3's log queued",
        cells: topSetAndLine,
        hidden: [],
        steps: [.log("w1d1.e0.s2", "150x8@7"), .edit(["D15": "1"]), .flush, .sync],
        mainCells: lowered(topSetAndLine, ["D15": "1"]),
        mainSets: ["e0.s0 RPE8 pending ", "e0.s1 RPE7 pending "]
    ),
    DropWorkbook(
        testDescription: "R1u as R1, with the log queued by a build from before the app read Drops",
        cells: topSetAndLine,
        hidden: [],
        steps: [.logAsMain("w1d1.e0.s2", "150x8@7"), .edit(["D15": "1"]), .flush, .sync],
        mainCells: lowered(topSetAndLine, ["D15": "1"]),
        mainSets: ["e0.s0 RPE8 pending ", "e0.s1 RPE7 pending "]
    ),
    DropWorkbook(
        testDescription: "R1s as R1, with Set 3 skipped",
        cells: topSetAndLine,
        hidden: [],
        steps: [.skip("w1d1.e0.s2"), .edit(["D15": "1"]), .flush, .sync],
        mainCells: lowered(topSetAndLine, ["D15": "1"]),
        mainSets: ["e0.s0 RPE8 pending ", "e0.s1 RPE7 pending "]
    ),
    DropWorkbook(
        testDescription: "R1f as R1, with a Set Flag on Set 3",
        cells: topSetAndLine,
        hidden: [],
        steps: [.flag("w1d1.e0.s2", painInHip), .edit(["D15": "1"]), .flush, .sync],
        mainCells: lowered(topSetAndLine, ["D15": "1"]),
        mainSets: ["e0.s0 RPE8 pending ", "e0.s1 RPE7 pending "]
    ),
    DropWorkbook(
        testDescription: "R1c the coach clears the second Line's Sets cell with the third Line's log queued",
        cells: threeLines,
        hidden: [],
        steps: [.log("w1d1.e0.s2", "140x8@6"), .edit(["D16": ""]), .flush, .sync],
        mainCells: lowered(threeLines, ["D16": ""]),
        mainSets: ["e0.s0 RPE8 pending ", "e0.s1 RPE6 pending "]
    ),
    DropWorkbook(
        testDescription: "R1h the coach hides the second Line with the third Line's log queued",
        cells: threeLines,
        hidden: [],
        steps: [.log("w1d1.e0.s2", "140x8@6"), .hide([16]), .flush, .sync],
        mainCells: threeLines,
        mainSets: ["e0.s0 RPE8 pending ", "e0.s1 RPE6 pending "]
    ),
    DropWorkbook(
        testDescription: "R1x the coach lowers the top count from 3 to 1 with two logs queued over two Drops",
        cells: twoDrops,
        hidden: [],
        steps: [.log("w1d1.e0.s2", "177x6@8"), .log("w1d1.e0.s3", "150x8@7"), .edit(["D15": "1"]), .flush, .sync],
        mainCells: lowered(twoDrops, ["D15": "1"]),
        mainSets: ["e0.s0 RPE8 pending ", "e0.s1 RPE7 pending "]
    )
]

@Test("A counted Set's queued write never lands on an added Drop", arguments: workbooks)
func aCountedSetsQueuedWriteNeverLandsOnAnAddedDrop(workbook: DropWorkbook) async throws {
    let replay = try await replayed(workbook)
    #expect(replay.cells == workbook.mainCells)
    #expect(replay.cellNotes == [:])
    #expect(workbook.mainSets.filter { !replay.sets.contains($0) } == [])
    #expect(replay.sets.filter { $0.hasPrefix("e0.") && !$0.contains(" pending ") } == [])
}
