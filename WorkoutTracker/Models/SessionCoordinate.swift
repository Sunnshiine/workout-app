import Foundation

/// Which Session an Exercise History entry was performed in: Block tab · Week number · Day number
/// (ADR-0012).
///
/// The entry's persisted `source` is this coordinate's `storageValue`, and ADR-0012 makes that string
/// the append-only table's dedup key. The encoding is therefore an identity, not a label — changing it
/// would make every stored entry miss dedup and re-append on the next sync. Everything the athlete
/// reads is a separate projection (`blockTab` as the sheet's Block header, `sessionLabel` as its
/// gutter), so a cosmetic change to how a Session reads on screen cannot re-key the store.
struct SessionCoordinate: Hashable, Sendable {
    let blockTab: String
    let weekNumber: Int
    let dayNumber: Int

    /// `Block 27 · W1 D1` — the canonical encoding every writer persists, and the ADR-0012 dedup key.
    var storageValue: String { blockTab + Self.separator + sessionLabel }

    /// `W1 D1` — the Session label, stated once so the Exercise History gutter (`DESIGN.md` §5.6) and
    /// the makeup queue's Open Exercise row cannot drift apart.
    var sessionLabel: String { Self.sessionLabel(weekNumber: weekNumber, dayNumber: dayNumber) }

    init(blockTab: String, weekNumber: Int, dayNumber: Int) {
        self.blockTab = blockTab
        self.weekNumber = weekNumber
        self.dayNumber = dayNumber
    }

    /// Reads back a persisted `source`, or `nil` when the value does not carry the canonical shape —
    /// a row written by a build that predates it, say.
    init?(storageValue: String) {
        guard let separator = storageValue.range(of: Self.separator, options: .backwards) else { return nil }
        let label = storageValue[separator.upperBound...].split(separator: " ")
        guard label.count == 2,
            let weekNumber = Self.number(label[0], markedBy: "W"),
            let dayNumber = Self.number(label[1], markedBy: "D")
        else { return nil }
        self.init(
            blockTab: String(storageValue[..<separator.lowerBound]),
            weekNumber: weekNumber,
            dayNumber: dayNumber
        )
    }

    /// The number behind a marker letter, as `W12` reads 12. `nil` for anything else.
    private static func number(_ component: Substring, markedBy marker: Character) -> Int? {
        guard component.first == marker else { return nil }
        return Int(component.dropFirst())
    }

    /// The Session label for a Week and Day that are not part of a stored coordinate — the live
    /// Session an Open Exercise was left behind in.
    static func sessionLabel(weekNumber: Int, dayNumber: Int) -> String {
        "W\(weekNumber) D\(dayNumber)"
    }

    /// How a stored `source` reads in the Exercise History sheet: its Block header, kept in the
    /// source's own quiet sentence case, and its `W1 D1` gutter. A value that does not decode keeps
    /// rendering whole as its own header with an empty gutter, rather than dropping out of the ledger.
    static func labels(forStoredValue stored: String) -> (blockHeader: String, sessionLabel: String) {
        guard let coordinate = SessionCoordinate(storageValue: stored) else { return (stored, "") }
        return (coordinate.blockTab, coordinate.sessionLabel)
    }

    private static let separator = " · "
}
