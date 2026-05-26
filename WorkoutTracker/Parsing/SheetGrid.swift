import Foundation

typealias SheetGrid = [[String]]

extension Array where Element == [String] {
    func cell(row: Int, col: Int) -> String {
        guard row >= 0, row < count, col >= 0, col < self[row].count else { return "" }
        return self[row][col]
    }
}

func a1ToIndex(_ a1: String) -> (row: Int, col: Int) {
    let reference = a1.uppercased()
    var col = 0
    var idx = reference.startIndex
    while idx < reference.endIndex, reference[idx].isLetter {
        guard let asciiValue = reference[idx].asciiValue else { break }
        col = col * 26 + Int(asciiValue - 64)  // A=1
        idx = reference.index(after: idx)
    }
    let row = Int(reference[idx...]) ?? 1
    return (row - 1, col - 1)
}

func columnName(_ zeroBasedColumn: Int) -> String {
    let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    var value = zeroBasedColumn + 1
    var result = ""
    while value > 0 {
        let remainder = (value - 1) % 26
        result.insert(letters[remainder], at: result.startIndex)
        value = (value - 1) / 26
    }
    return result
}

func indexToA1(row: Int, col: Int) -> String {
    "\(columnName(col))\(row + 1)"
}

func quotedSheetName(_ name: String) -> String {
    "'\(name.replacingOccurrences(of: "'", with: "''"))'"
}

func singleCellRange(tabName: String, row: Int, col: Int) -> String {
    "\(quotedSheetName(tabName))!\(indexToA1(row: row, col: col))"
}
