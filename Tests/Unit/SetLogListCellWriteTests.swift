import Foundation
import Testing

@testable import WorkoutTracker

/// Pins the byte-exact Notes-cell value the planner produces when a Set's slot sits past the end of
/// the existing Set-Log list, so the list has to be padded before the Set's own token lands.
@Test func padsEarlierSlotsWhenALaterSetLogsFirst() throws {
    let planner = SheetWritePlanner()
    let grid = gridFromA1(
        [
            "C12": "Day 1",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Notes",
            "C15": "Comp SQ", "D15": "1", "F15": "5",
            "D16": "2", "F16": "7",
            "C17": "Hip Thrust", "D17": "2"
        ],
        rows: 26,
        cols: 30
    )
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Comp SQ",
        setIndex: 2,
        column: .notes,
        operation: .upsert,
        valueToWrite: "140x7@9",
        expectedCurrentValue: ""
    )

    let update = try planner.plan(request, in: grid)

    #expect(update.range == "'Block 27'!J16")
    #expect(update.value == ", 140x7@9")
}
