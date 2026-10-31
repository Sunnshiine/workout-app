import Foundation
import Testing

@testable import WorkoutTracker

@Test(
    "The card's control names the timed effort",
    arguments: [
        ("Start w/ 10 sec hold", "40 sec", "10 s hold", "10 second hold"),
        (nil, "40 sec", "40 s", "40 second Set"),
        ("Start w/ 1:30 hold", "8", "1:30 hold", "90 second hold"),
        (nil, "25 min", "25 min", "25 minute Set"),
        (nil, "0:59", "59 s", "59 second Set"),
        (nil, "1 min", "1 min", "1 minute Set")
    ] as [(String?, String, String, String)]
)
func theCardsControlNamesTheTimedEffort(coachNote: String?, reps: String, label: String, spoken: String) throws {
    let effort = try #require(TimedEffort(coachNote: coachNote, reps: PrescribedReps(reps)))

    #expect(effort.controlLabel == label)
    #expect(effort.spokenLabel == spoken)
}

private let start = Date(timeIntervalSinceReferenceDate: 1_000)

private func run(_ effort: TimedEffort) -> CountdownRun {
    CountdownRun(
        effort: effort,
        owner: CountdownRun.Owner(
            session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
            set: ActiveSetID(exerciseOrder: 1, setIndex: 0)
        ),
        start: start
    )
}

@Test func theFaceCountsTheLeadInThenTheHoldThenSaysItIsDone() throws {
    let hold = run(.openingHold(try #require(EffortDuration("10 sec"))))
    let faces = [0, 4, 5, 14, 15].map { EffortCountdownFace(hold, at: start.addingTimeInterval($0)) }

    #expect(faces.map(\.caption) == ["Get set", "Get set", "Hold", "Hold", "Done"])
    #expect(faces.map(\.numeral) == ["5", "1", "10", "1", "0"])
    #expect(faces.map(\.progress) == [0, 0, 0, 0.9, 1])
    #expect(faces.map(\.hint) == ["Tap to stop", "Tap to stop", "Tap to stop", "Tap to stop", "Tap to close"])
    #expect(
        faces.map(\.accessibilityValue) == ["Starts in 5", "Starts in 1", "Hold, 10 seconds left", "Hold, 1 second left", "Done"]
    )
}

@Test func aTimedSetOfMinutesShowsItsSecondsLeftAsAClock() throws {
    let timedSet = run(.timedSet(try #require(EffortDuration("1:30"))))
    let faces = [5, 35, 36, 95].map { EffortCountdownFace(timedSet, at: start.addingTimeInterval($0)) }

    #expect(faces.map(\.caption) == ["Go", "Go", "Go", "Time"])
    #expect(faces.map(\.numeral) == ["1:30", "1:00", "59", "0"])
}
