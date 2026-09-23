import Foundation

enum FixtureDatesAreLiteral {
    static func dateInitializerIsFlagged() -> Date {
        Date()
    }

    static func dateNowIsFlagged() -> Date {
        Date.now
    }

    static func timeIntervalSinceNowIsFlagged() -> Date {
        Date(timeIntervalSinceNow: -86_400)
    }

    static func currentTimeZoneIsFlagged() -> TimeZone {
        TimeZone.current
    }

    static func currentCalendarIsFlagged() -> Calendar {
        Calendar.current
    }

    static func autoupdatingCurrentIsFlagged() -> TimeZone {
        TimeZone.autoupdatingCurrent
    }

    static func nowShorthandPasses() -> Date {
        .now
    }

    static func dateFormatterOnTheMachineTimeZonePasses() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func literalEpochDatePasses() -> Date {
        Date(timeIntervalSince1970: 1_758_000_000)
    }

    static func dateInACommentPasses() -> Date {
        // Date() moves with the clock.
        Date(timeIntervalSince1970: 0)
    }

    static func dateInAStringPasses() -> String {
        "Date.now"
    }
}
