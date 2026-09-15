import Foundation
import Testing

@testable import WorkoutTracker

@Test func restPillPresentationKeepsVoiceOverLabelWithoutVisibleTypeLabel() {
    let presentation = RestPillPresentation(kind: .superset, remaining: 83, duration: 150)

    #expect(presentation.visibleTypeLabel == nil)
    #expect(presentation.countdownText == "1:23")
    #expect(presentation.accessibilityLabel == "Superset rest, 1 minute 23 seconds remaining")
}

@Test func restPillPresentationUsesSecondTickDigitsAndContinuousProgress() {
    let atWholeSecond = RestPillPresentation(kind: .standard, remaining: 60, duration: 120)
    let insideSameDisplayedSecond = RestPillPresentation(kind: .standard, remaining: 59.5, duration: 120)

    #expect(atWholeSecond.countdownText == "1:00")
    #expect(insideSameDisplayedSecond.countdownText == "1:00")
    #expect(insideSameDisplayedSecond.progressFraction < atWholeSecond.progressFraction)
    #expect(insideSameDisplayedSecond.progressFraction > 0)
}

@Test func restPillPresentationSpeaksEveryPluralizationOfTheRemainingDuration() {
    func label(remaining: TimeInterval) -> String {
        RestPillPresentation(kind: .standard, remaining: remaining, duration: 300).accessibilityLabel
    }

    #expect(label(remaining: 0) == "Rest, 0 seconds remaining")
    #expect(label(remaining: 61) == "Rest, 1 minute 1 second remaining")
    #expect(label(remaining: 60) == "Rest, 1 minute remaining")
    #expect(label(remaining: 1) == "Rest, 1 second remaining")
    #expect(label(remaining: 150) == "Rest, 2 minutes 30 seconds remaining")
    #expect(label(remaining: 120) == "Rest, 2 minutes remaining")
    #expect(label(remaining: 2) == "Rest, 2 seconds remaining")
}

@Test func restPillPresentationHandlesExpiredAndInvalidDurations() {
    let expired = RestPillPresentation(kind: .standard, remaining: -1, duration: 120)
    let invalidDuration = RestPillPresentation(kind: .standard, remaining: 30, duration: 0)

    #expect(expired.countdownText == "0:00")
    #expect(expired.progressFraction == 0)
    #expect(invalidDuration.progressFraction == 0)
}
