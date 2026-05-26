import Testing

@testable import WorkoutTracker

@Test func a1HelperPlacesValues() {
    let grid = gridFromA1(["C12": "Day 1", "S12": "Day 2"], rows: 13, cols: 20)
    #expect(grid.cell(row: 11, col: 2) == "Day 1")  // C12 -> r11,c2 (0-based)
    #expect(grid.cell(row: 11, col: 18) == "Day 2")  // S12 -> r11,c18
    #expect(grid.cell(row: 0, col: 0) == "")  // empty default
    #expect(grid.cell(row: 99, col: 99) == "")  // out of bounds -> ""
}
