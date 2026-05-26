import Foundation

typealias SheetGrid = [[String]]

extension Array where Element == [String] {
    func cell(row: Int, col: Int) -> String {
        guard row >= 0, row < count, col >= 0, col < self[row].count else { return "" }
        return self[row][col]
    }
}

func a1ToIndex(_ a1: String) -> (row: Int, col: Int) {
    var col = 0
    var idx = a1.startIndex
    while idx < a1.endIndex, a1[idx].isLetter {
        col = col * 26 + (Int(a1[idx].asciiValue! - 64))  // A=1
        idx = a1.index(after: idx)
    }
    let row = Int(a1[idx...]) ?? 1
    return (row - 1, col - 1)
}
