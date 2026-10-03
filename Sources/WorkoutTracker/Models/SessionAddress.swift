import Foundation

/// A Session by its 1-based Week number and Day number: `w1d3`.
///
/// It carries no Block tab, so it re-resolves against whichever Block is cached: the Viewed Session
/// survives a sheet switch, and a CLI address names a Session of the cached Block. A holder that
/// must tell Blocks apart holds a `SessionCoordinate` or a `SessionReparseIdentity`. Deliberately not `Comparable`: the one
/// persisted order is the current-Session override's `(week - 1) * 7 + day`.
public struct SessionAddress: StringCodedAddress {
    public let week: Int
    public let day: Int

    public init(week: Int, day: Int) {
        self.week = week
        self.day = day
    }

    public init?(_ description: String) {
        guard let match = description.wholeMatch(of: /w(\d+)d(\d+)/), let week = Int(match.1), let day = Int(match.2) else {
            return nil
        }
        self.init(week: week, day: day)
    }

    public var description: String { "w\(week)d\(day)" }

    /// `W1 D1` — the Session label, stated once so the Exercise History gutter (`DESIGN.md` §5.6) and
    /// the makeup queue's Open Exercise row cannot drift apart.
    var sessionLabel: String { "W\(week) D\(day)" }
}

extension Week {
    func address(of session: Session) -> SessionAddress {
        SessionAddress(week: number, day: session.dayNumber)
    }
}

extension Session {
    /// Nil when the Session has no Week. Each caller states its own fallback.
    var address: SessionAddress? { week?.address(of: self) }

    var reparseIdentity: SessionReparseIdentity {
        guard let week else { return .weekless(dayNumber: dayNumber) }
        return .inWeek(week.address(of: self), blockTab: week.block?.tabName)
    }
}

/// Which Session a live model is, in terms that still match after a sync replaces the Block.
///
/// The Block tab is reached through the Week, so a Session with no Week has no tab either: the two
/// cases cover every shape a Session's graph can take.
enum SessionReparseIdentity: Hashable, Sendable {
    /// `blockTab` is nil when the Week has no Block.
    case inWeek(SessionAddress, blockTab: String?)
    case weekless(dayNumber: Int)
}

extension ParsedWeek {
    func address(of session: ParsedSession) -> SessionAddress {
        SessionAddress(week: number, day: session.dayNumber)
    }
}

extension Block {
    /// The first Week with the address's number, then the first Session in it with its Day.
    func session(at address: SessionAddress) -> Session? {
        weeks.first { $0.number == address.week }?.sessions.first { $0.dayNumber == address.day }
    }
}
