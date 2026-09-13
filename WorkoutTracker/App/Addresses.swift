import Foundation

/// An address that reads and writes as one string: parsing is strict, and the JSON form is the
/// same string an agent copies from one command's output into the next command.
public protocol StringCodedAddress: Hashable, Sendable, LosslessStringConvertible, Codable {}

extension StringCodedAddress {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let address = Self(raw) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Not a \(Self.self): \(raw)")
            )
        }
        self = address
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// A Session by its 1-based Week number and Day number: `w1d3`.
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
}

/// An Exercise by its Session and its 0-based `Exercise.order`: `w1d3.e0`.
public struct ExerciseAddress: StringCodedAddress {
    public let session: SessionAddress
    public let order: Int

    public init(session: SessionAddress, order: Int) {
        self.session = session
        self.order = order
    }

    public init?(_ description: String) {
        guard
            let match = description.wholeMatch(of: /(w\d+d\d+)\.e(\d+)/),
            let session = SessionAddress(String(match.1)),
            let order = Int(match.2)
        else { return nil }
        self.init(session: session, order: order)
    }

    public var description: String { "\(session).e\(order)" }
}

/// A Set by its Exercise and its 0-based `ExerciseSet.index`: `w1d3.e0.s2`.
public struct SetAddress: StringCodedAddress {
    public let exercise: ExerciseAddress
    public let index: Int

    public init(exercise: ExerciseAddress, index: Int) {
        self.exercise = exercise
        self.index = index
    }

    public init?(_ description: String) {
        guard
            let match = description.wholeMatch(of: /(w\d+d\d+\.e\d+)\.s(\d+)/),
            let exercise = ExerciseAddress(String(match.1)),
            let index = Int(match.2)
        else { return nil }
        self.init(exercise: exercise, index: index)
    }

    public var description: String { "\(exercise).s\(index)" }
}
