import Foundation
import Testing

@testable import WorkoutTracker

@Test func restIntervalDerivesEndFromStartAndDuration() {
    let start = Date(timeIntervalSinceReferenceDate: 1000)
    let interval = RestInterval(start: start, duration: 120, kind: .standard)

    #expect(interval.end == start.addingTimeInterval(120))
    #expect(interval.duration == 120)
    #expect(interval.kind == .standard)
}

@Test func restIntervalStartPlusDurationEqualsEndForEveryConstruction() {
    let start = Date(timeIntervalSinceReferenceDate: 42)
    for seconds in stride(from: 30.0, through: 600.0, by: 15) {
        let interval = RestInterval(start: start, duration: seconds, kind: .superset)
        #expect(interval.start.addingTimeInterval(interval.duration) == interval.end)
        #expect(interval.start.addingTimeInterval(interval.remaining(at: start)) == interval.end)
    }
}

@Test func restIntervalRemainingClampsToZeroAtOrAfterEnd() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let interval = RestInterval(start: start, duration: 90, kind: .standard)

    #expect(interval.remaining(at: start) == 90)
    #expect(interval.remaining(at: start.addingTimeInterval(30)) == 60)
    #expect(interval.remaining(at: interval.end) == 0)
    #expect(interval.remaining(at: interval.end.addingTimeInterval(10)) == 0)
}

@Test func restIntervalElapsedClampsToZeroAndDuration() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let interval = RestInterval(start: start, duration: 90, kind: .standard)

    #expect(interval.elapsed(at: start.addingTimeInterval(-5)) == 0)
    #expect(interval.elapsed(at: start) == 0)
    #expect(interval.elapsed(at: start.addingTimeInterval(30)) == 30)
    #expect(interval.elapsed(at: interval.end) == 90)
    #expect(interval.elapsed(at: interval.end.addingTimeInterval(10)) == 90)
}

@Test func restIntervalProgressFractionStaysWithinUnitRange() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let interval = RestInterval(start: start, duration: 120, kind: .standard)

    #expect(interval.progressFraction(at: start) == 1)
    #expect(interval.progressFraction(at: start.addingTimeInterval(60)) == 0.5)
    #expect(interval.progressFraction(at: interval.end) == 0)
    #expect(interval.progressFraction(at: interval.end.addingTimeInterval(10)) == 0)

    let zeroDuration = RestInterval(start: start, duration: 0, kind: .standard)
    #expect(zeroDuration.progressFraction(at: start) == 0)
}

@Test func restIntervalCountdownTextCeilsRemainingSeconds() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let interval = RestInterval(start: start, duration: 150, kind: .superset)

    // 83 remaining -> "1:23"
    #expect(interval.countdownText(at: interval.end.addingTimeInterval(-83)) == "1:23")
    // 59.5 remaining ceils to 60 -> "1:00"
    #expect(interval.countdownText(at: interval.end.addingTimeInterval(-59.5)) == "1:00")
    // At or past end -> "0:00"
    #expect(interval.countdownText(at: interval.end) == "0:00")
    #expect(interval.countdownText(at: interval.end.addingTimeInterval(5)) == "0:00")
}

@Test func restIntervalSharedFormatterRendersMinutesAndSeconds() {
    #expect(RestInterval.countdownText(seconds: 0) == "0:00")
    #expect(RestInterval.countdownText(seconds: 30) == "0:30")
    #expect(RestInterval.countdownText(seconds: 83) == "1:23")
    #expect(RestInterval.countdownText(seconds: 120) == "2:00")
    #expect(RestInterval.countdownText(seconds: 600) == "10:00")
}
