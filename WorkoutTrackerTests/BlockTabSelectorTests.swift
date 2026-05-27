import Testing

@testable import WorkoutTracker

@Test func picksHighestNumberedBlockTab() {
    let titles = ["Intro", "Block 1", "Block - 26", "Block 27", "Sub workout", "RPE Chart"]
    #expect(currentBlockTab(from: titles) == "Block 27")
}

@Test func handlesDashAndNoDashNaming() {
    #expect(currentBlockTab(from: ["Block 3", "Block - 4", "Block - 28"]) == "Block - 28")
}

@Test func returnsNilWhenNoBlockTabs() {
    #expect(currentBlockTab(from: ["Intro", "Mobility Drills"]) == nil)
}

@Test func sortsHistoricalBlockTabsDescendingExcludingCurrentAndNonBlocks() {
    let titles = ["Intro", "Block 1", "Block - 26", "Block 27", "Sub workout", "Block 3"]

    #expect(sortedHistoricalTabs(from: titles, excluding: "Block 27") == ["Block - 26", "Block 3", "Block 1"])
}
