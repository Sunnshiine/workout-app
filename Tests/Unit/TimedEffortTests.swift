import Testing

@testable import WorkoutTracker

@Test func anOpeningHoldInTheCoachNoteIsTheTimedEffortOfEverySetOfItsExercise() {
    let exercise = Exercise(name: "2-3:1:0 BB RDL", coachNote: "Start w/ 10 sec hold, proceed to rep range.", order: 0)
    exercise.sets = (0..<3).map { index in
        ExerciseSet(index: index, prescribedReps: "8", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
    }

    #expect(exercise.sets.map(\.timedEffort?.duration.seconds) == [10, 10, 10])
}

@Test func aTimedSetsDurationIsItsTimedEffort() {
    let exercise = Exercise(name: "Farmer Carry", coachNote: "Tall posture.", order: 0)
    let set = ExerciseSet(index: 0, prescribedReps: "40 sec", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    exercise.sets = [set]

    #expect(set.timedEffort == TimedEffort(coachNote: nil, reps: PrescribedReps("40 sec")))
    #expect(set.timedEffort?.duration.seconds == 40)
    guard case .timedSet = set.timedEffort else {
        Issue.record("40 sec read as \(String(describing: set.timedEffort))")
        return
    }
}

@Test func anOpeningHoldOutranksATimedSetsDuration() {
    let effort = TimedEffort(coachNote: "15 sec hold at the top", reps: PrescribedReps("40 sec"))

    guard case .openingHold(let hold) = effort else {
        Issue.record("read as \(String(describing: effort))")
        return
    }
    #expect(hold.seconds == 15)
}

@Test(
    "A Set with no hold at the start and no Timed Set has no timed effort",
    arguments: [
        (nil, "5"),
        ("rest 90 sec", "8-10"),
        ("Super set w/ 0:5:0 Push Ups for AMRAP", "AMRAP"),
        ("Pause every rep.", "1-2-3-3-2-1")
    ] as [(String?, String)]
)
func aSetWithNoHoldAndNoTimedSetHasNoTimedEffort(coachNote: String?, reps: String) {
    #expect(TimedEffort(coachNote: coachNote, reps: PrescribedReps(reps)) == nil)
}
