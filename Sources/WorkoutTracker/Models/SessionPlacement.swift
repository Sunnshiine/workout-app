import Foundation

/// Where a Session sits (`CONTEXT.md`): its Session Coordinate while a Block holds it, or a Detached
/// Session, which knows only its Day number.
///
/// A sync deletes the cached Block and inserts the re-parsed one, so a Session held across it is
/// detached. The on-disk store then drops its Week as well as its Block, while an in-memory store
/// keeps the Week, so the Block is what decides.
enum SessionPlacement: Hashable, Sendable {
    case inBlock(SessionCoordinate)
    case detached(dayNumber: Int)

    var coordinate: SessionCoordinate? {
        guard case .inBlock(let coordinate) = self else { return nil }
        return coordinate
    }

    /// `Week 2 · Day 3` with the surface's own `separator`, or `Day 3` for a Detached Session, so
    /// no surface reads a Week it no longer knows as `Week 0`.
    func locationText(separator: String) -> String {
        switch self {
        case .inBlock(let coordinate):
            "Week \(coordinate.address.week)\(separator)Day \(coordinate.address.day)"
        case .detached(let dayNumber):
            "Day \(dayNumber)"
        }
    }
}

extension Session {
    /// Nil for a Detached Session.
    var block: Block? { week?.block }

    var placement: SessionPlacement {
        guard let week, let block = week.block else { return .detached(dayNumber: dayNumber) }
        return .inBlock(SessionCoordinate(blockTab: block.tabName, address: week.address(of: self)))
    }

    /// Nil for a Detached Session.
    var address: SessionAddress? { placement.coordinate?.address }
}
