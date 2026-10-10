import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func theBackLabelNamesTheCurrentSessionsWeekAndDay() {
    let session = Session(dayNumber: 3, date: nil)
    session.week = Week(number: 2)

    #expect(OffLiveEdgePresentation(currentSession: session).backLabel == "Back to W2 D3")
}

@MainActor
@Test func theBackLabelNamesOnlyTheDayOfACurrentSessionWithoutAWeek() {
    let session = Session(dayNumber: 4, date: nil)

    #expect(OffLiveEdgePresentation(currentSession: session).backLabel == "Back to Day 4")
}

@MainActor
@Test func theBackLabelIsBareWithoutACurrentSession() {
    #expect(OffLiveEdgePresentation(currentSession: nil).backLabel == "Back")
}
