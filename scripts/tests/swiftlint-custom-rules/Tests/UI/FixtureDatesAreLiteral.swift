import Foundation

enum FixtureDatesAreLiteral {
    static func wallClockDeadlineInUITestsPasses() -> Date {
        Date().addingTimeInterval(10)
    }
}
