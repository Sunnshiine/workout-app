import Foundation
import SwiftData

@Model
final class Block {
    @Attribute(.unique) var tabName: String
    var squatTM: Double?
    var benchTM: Double?
    var deadliftTM: Double?
    @Relationship(deleteRule: .cascade, inverse: \Week.block) var weeks: [Week] = []

    init(tabName: String, squatTM: Double?, benchTM: Double?, deadliftTM: Double?) {
        self.tabName = tabName
        self.squatTM = squatTM
        self.benchTM = benchTM
        self.deadliftTM = deadliftTM
    }
}

@Model
final class Week {
    var number: Int
    var block: Block?
    @Relationship(deleteRule: .cascade, inverse: \Session.week) var sessions: [Session] = []

    init(number: Int) { self.number = number }
}

@Model
final class Session {
    var dayNumber: Int
    var date: Date?
    var week: Week?
    @Relationship(deleteRule: .cascade, inverse: \Exercise.session) var exercises: [Exercise] = []

    init(dayNumber: Int, date: Date?) {
        self.dayNumber = dayNumber
        self.date = date
    }
}

// MARK: - Set State aggregation

extension Session {
    /// A Session is complete when every Set across its Exercises is settled
    /// (Logged or Skipped). A Session holding zero Sets — including an
    /// Unavailable Session with zero Exercises — is deliberately *not* complete.
    var isComplete: Bool {
        exercises.allSetsComplete
    }

    /// Count of settled (Logged or Skipped) Sets across all Exercises.
    var completedSetCount: Int {
        exercises.completedSetCount
    }

    /// Count of all prescribed Sets across all Exercises.
    var totalSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    /// Count of still-Pending Sets across all Exercises.
    var pendingSetCount: Int {
        exercises.reduce(0) { $0 + $1.pendingSetCount }
    }
}
