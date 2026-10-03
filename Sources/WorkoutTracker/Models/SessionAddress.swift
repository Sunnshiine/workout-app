import Foundation

/// A Session by its 1-based Week number and Day number: `w1d3`.
///
/// It carries no Block tab, so it re-resolves against whichever Block is cached.
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

    var sessionLabel: String { "W\(week) D\(day)" }
}

extension Week {
    func address(of session: Session) -> SessionAddress {
        SessionAddress(week: number, day: session.dayNumber)
    }
}

extension Session {
    var address: SessionAddress? { week?.address(of: self) }

    var reparseIdentity: SessionReparseIdentity {
        guard let week else { return .weekless(dayNumber: dayNumber) }
        return .inWeek(week.address(of: self), blockTab: week.block?.tabName)
    }
}

enum SessionReparseIdentity: Hashable, Sendable {
    case inWeek(SessionAddress, blockTab: String?)
    case weekless(dayNumber: Int)
}

extension ParsedWeek {
    func address(of session: ParsedSession) -> SessionAddress {
        SessionAddress(week: number, day: session.dayNumber)
    }
}

extension Block {
    func session(at address: SessionAddress) -> Session? {
        weeks.first { $0.number == address.week }?.sessions.first { $0.dayNumber == address.day }
    }
}
