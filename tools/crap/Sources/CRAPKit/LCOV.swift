import Foundation

public enum LCOV {
    /// file path -> line -> execution count, from `DA:<line>,<count>` records only.
    public static func parse(text: String) -> [String: [Int: Int]] {
        var result: [String: [Int: Int]] = [:]
        var current: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("SF:") {
                current = String(line.dropFirst(3))
            } else if line == "end_of_record" {
                current = nil
            } else if line.hasPrefix("DA:"), let file = current {
                let fields = line.dropFirst(3).split(separator: ",")
                guard fields.count >= 2, let number = Int(fields[0]), let count = Int(fields[1]) else { continue }
                result[file, default: [:]][number, default: 0] += count
            }
        }
        return result
    }
}
