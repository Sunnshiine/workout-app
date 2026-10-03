import Foundation

/// Which Session of which Block: Block tab · Session Address. Queued writes and Exercise History
/// entries (ADR-0012) hold one.
///
/// The entry's persisted `source` is this coordinate's `storageValue`, and ADR-0012 makes that string
/// the append-only table's dedup key. The encoding is therefore an identity, not a label — changing it
/// would make every stored entry miss dedup and re-append on the next sync.
struct SessionCoordinate: Hashable, Sendable {
    let blockTab: String
    let address: SessionAddress

    /// `Block 27 · W1 D1` — the canonical encoding every writer persists, and the ADR-0012 dedup key.
    var storageValue: String { blockTab + Self.separator + "W\(address.week) D\(address.day)" }

    init(blockTab: String, address: SessionAddress) {
        self.blockTab = blockTab
        self.address = address
    }

    /// Reads back a persisted `source`, or `nil` when the value does not carry the canonical shape —
    /// a row written by a build that predates it, say.
    init?(storageValue: String) {
        guard let separator = storageValue.range(of: Self.separator, options: .backwards) else { return nil }
        let label = storageValue[separator.upperBound...].split(separator: " ")
        guard label.count == 2,
            label[0].hasPrefix("W"), label[1].hasPrefix("D"),
            let weekNumber = Int(label[0].dropFirst()),
            let dayNumber = Int(label[1].dropFirst())
        else { return nil }
        self.init(
            blockTab: String(storageValue[..<separator.lowerBound]),
            address: SessionAddress(week: weekNumber, day: dayNumber)
        )
    }

    /// How a stored `source` reads in the Exercise History sheet: its Block header, kept in the
    /// source's own quiet sentence case, and its `W1 D1` gutter. A value that does not decode keeps
    /// rendering whole as its own header with an empty gutter, rather than dropping out of the ledger.
    static func labels(forStoredValue stored: String) -> (blockHeader: String, sessionLabel: String) {
        guard let coordinate = SessionCoordinate(storageValue: stored) else { return (stored, "") }
        return (coordinate.blockTab, coordinate.address.sessionLabel)
    }

    private static let separator = " · "
}
