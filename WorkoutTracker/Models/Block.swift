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
