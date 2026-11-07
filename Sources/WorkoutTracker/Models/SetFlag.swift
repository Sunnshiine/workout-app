import Foundation

public enum SetFlagKind: String, Codable, CaseIterable, Sendable {
    case pain, technique, swapped, other

    /// The word on the sheet's chip and in the line the coach reads.
    public var label: String {
        switch self {
        case .pain: "Pain"
        case .technique: "Technique"
        case .swapped: "Swapped"
        case .other: "Other"
        }
    }
}

/// What the athlete tells the coach about one Set. Nil for what the coach could not use: Other with
/// no words, or more words than a Cell Note line should carry. The words always fit one line, so a
/// later sync reads back exactly the line the flush wrote.
public struct SetFlag: Codable, Equatable, Sendable {
    public static let maximumTextLength = 280

    public let kind: SetFlagKind
    public let text: String?

    public init?(kind: SetFlagKind, text: String?) {
        let words = (text ?? "").split(whereSeparator: \.isNewline).joined(separator: " ").trimmed
        guard words.count <= Self.maximumTextLength, kind != .other || !words.isEmpty else { return nil }
        self.kind = kind
        self.text = words.isEmpty ? nil : words
    }
}

/// One Set Flag as the coach reads it in a Cell Note, and as a later sync reads it back:
/// `Set 2 · Pain: left hip pinch on the way up`. The line names its Set because Sets can share one
/// Notes cell.
struct SetFlagLine: Equatable, Sendable {
    let setIndex: Int
    let flag: SetFlag

    init(setIndex: Int, flag: SetFlag) {
        self.setIndex = setIndex
        self.flag = flag
    }

    /// Nil for any line that is not this sentence, which leaves a coach's own words alone.
    init?(parsing line: String) {
        guard
            let match = line.trimmed.wholeMatch(of: /Set ([1-9][0-9]*) · (\w+)(?:: (.+))?/),
            let number = Int(match.1),
            let kind = SetFlagKind.allCases.first(where: { $0.label == match.2 }),
            let flag = SetFlag(kind: kind, text: match.3.map(String.init))
        else { return nil }
        self.init(setIndex: number - 1, flag: flag)
    }

    var text: String {
        let head = "Set \(setIndex + 1) · \(flag.kind.label)"
        return flag.text.map { "\(head): \($0)" } ?? head
    }

    /// The Set Flag lines a Cell Note holds, skipping the coach's words around them.
    static func all(in cellNote: String) -> [SetFlagLine] {
        cellNote.split(whereSeparator: \.isNewline).compactMap { SetFlagLine(parsing: String($0)) }
    }

    /// The Cell Note once `line` is in it. What it already holds stays verbatim, so a coach's words
    /// survive. A line it already holds is not added again, so replaying a flush whose response was
    /// lost leaves one line, not two.
    static func cellNote(_ cellNote: String, adding line: String) -> String {
        let holdsLine = cellNote.split(whereSeparator: \.isNewline).contains { String($0).trimmed == line }
        if holdsLine { return cellNote }
        guard let last = cellNote.last else { return line }
        return last.isNewline ? cellNote + line : "\(cellNote)\n\(line)"
    }
}

/// Where a Set Flag stands on its way to the coach. The cases run most to least pressing, so the one
/// mark a Set shows speaks for the flag that most needs the athlete.
public enum SetFlagStanding: String, Codable, CaseIterable, Sendable {
    /// The flush took it off the queue without writing it, and nothing attempts it again.
    case refused
    case unsynced
    case landed
}

struct SetFlagEntry: Codable, Equatable, Sendable {
    let flag: SetFlag
    var standing: SetFlagStanding
}
