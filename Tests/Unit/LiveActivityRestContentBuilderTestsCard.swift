import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

/// What the Lock Screen card holds for the next Set: the Cadence and the Coach Note apart, and the
/// weight the stage would show for it.
@MainActor
@Suite struct LiveActivityRestCardContentTests {
    @Test func anOrdinarySetCarriesTheCadenceTheCoachNoteAndTheWeightTheStageHolds() throws {
        let exercise = exercise("3:1:1 Bench Press", coachNote: "Pause on the chest.", next: ("5", "RPE 8"))
        let focus = ActiveSetFocusManager(session: nil)
        focus.cardShows(SetLogDraft(weight: .pounds(235), reps: 5, rpe: .eight), for: ActiveSetID(exerciseOrder: 0, setIndex: 1))

        let card = try content(after: exercise, focus: focus)

        #expect(card.exerciseName == "Bench Press")
        #expect(card.cadence == "3:1:1")
        #expect(card.coachNote == "Pause on the chest.")
        #expect(card.weightValue == "235")
        #expect(card.weightUnit == "lbs")
        #expect(card.prescribedReps == "5")
        #expect(card.prescribedLoad == "RPE 8")
    }

    /// `Drop 17.5%` off a 300 lb Set is 247.5 lb, the weight the stage pre-fills, never the percentage.
    @Test func aDropSetCarriesTheWeightWorkedOutFromTheSetBefore() throws {
        let exercise = exercise("BB RDL", coachNote: nil, next: ("8", "Drop 17.5%"), loggedAt: 300)

        let card = try content(after: exercise)

        #expect(card.weightValue == "247.5")
        #expect(card.weightUnit == "lbs")
    }

    @Test func anExerciseWithNoCadenceCarriesNone() throws {
        let card = try content(after: exercise("Bench Press", coachNote: "Pause on the chest."))

        #expect(card.cadence == nil)
        #expect(card.coachNote == "Pause on the chest.")
    }

    @Test(arguments: [nil, "", "  \n\t "])
    func anExerciseWithNoWordsInItsCoachNoteCarriesNone(note: String?) throws {
        let card = try content(after: exercise("3:1:1 Bench Press", coachNote: note))

        #expect(card.cadence == "3:1:1")
        #expect(card.coachNote == nil)
    }

    @Test func aRangeCadenceCarriesWholeAndLeavesTheName() throws {
        let card = try content(after: exercise("2-3:1:0 BB RDL", coachNote: "Start w/ 10 sec hold, proceed to rep range."))

        #expect(card.exerciseName == "BB RDL")
        #expect(card.cadence == "2-3:1:0")
        #expect(card.coachNote == "Start w/ 10 sec hold, proceed to rep range.")
    }

    /// A note written over several lines reads as one, and a long one stops at 120 characters so it
    /// cannot take the Live Activity's 4 KB.
    @Test func aLongCoachNoteCarriesOneLineCutAt120Characters() throws {
        let sentence = "Belt off, knee wraps on.\nStop the Set the moment the bar speed drops off at all,   and note how far it slowed."
        let card = try content(after: exercise("Back Squat", coachNote: sentence + "\n\n" + sentence))

        let oneLine = sentence.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(card.coachNote == String((oneLine + " " + oneLine).prefix(120)))
        #expect(card.coachNote?.count == 120)
    }

    @Test func extremeValuesCarryAsTheStageHoldsThem() throws {
        let exercise = exercise(
            "10-20:10-20:10-20 Paused Low-Bar Competition Back Squat w/ Safety Squat Bar",
            coachNote: nil,
            next: ("AMRAP", "Start conservative and work up to a heavy single")
        )
        let focus = ActiveSetFocusManager(session: nil)
        focus.cardShows(SetLogDraft(weight: .pounds(1002.5), reps: nil, rpe: nil), for: ActiveSetID(exerciseOrder: 0, setIndex: 1))

        let card = try content(after: exercise, focus: focus)

        #expect(card.exerciseName == "Paused Low-Bar Competition Back Squat w/ Safety Squat Bar")
        #expect(card.cadence == "10-20:10-20:10-20")
        #expect(card.weightValue == "1002.5")
        #expect(card.prescribedReps == "AMRAP")
        #expect(card.prescribedLoad == "Start conservative and work up to a heavy single")
    }

    #if os(iOS)
        /// The card and the island draw the same line from the split as they drew from the joined one.
        @Test(
            arguments: [
                ("2-3:1:0 BB RDL", "Start w/ 10 sec hold", "2-3:1:0 · Start w/ 10 sec hold"),
                ("3:1:1 Leg Press", nil, "3:1:1"),
                ("Bench Press", "Pause on the chest\n\nfull lockout", "Pause on the chest full lockout"),
                ("Bench Press", "  ", nil)
            ] as [(ExerciseName, String?, String?)]
        )
        func theDrawnLineReadsTheCadenceThenTheCoachNote(name: ExerciseName, note: String?, line: String?) throws {
            let state = WorkoutActivityAttributes.ContentState(
                restContent: try content(after: exercise(name, coachNote: note)),
                dictation: nil
            )

            #expect(state.cadenceAndCoachNote == line)
        }
    #endif

    /// An Exercise whose first Set is logged, and the Set the card shows after it.
    private func exercise(
        _ name: ExerciseName,
        coachNote: String?,
        next: (reps: String, load: String) = ("5", "RPE 8"),
        loggedAt pounds: Double = 225
    ) -> Exercise {
        let exercise = Exercise(name: name, coachNote: coachNote)
        let logged = ExerciseSet(index: 0, prescribedReps: next.reps, prescribedLoad: next.load, percentOneRM: nil, state: .logged)
        logged.setLog = SetLog(weight: .pounds(pounds), reps: 8, rpe: .eight)
        exercise.sets = [
            logged,
            ExerciseSet(index: 1, prescribedReps: next.reps, prescribedLoad: next.load, percentOneRM: nil, state: .pending)
        ]
        return exercise
    }

    private func content(
        after exercise: Exercise,
        focus: ActiveSetFocusManager = ActiveSetFocusManager(session: nil)
    ) throws -> LiveActivityRestContent {
        let session = makeSingleSession(exercises: [exercise])
        let logged = try #require(exercise.sets.first { $0.index == 0 })
        return try #require(
            LiveActivityRestContentBuilder.content(
                afterLogging: logged,
                in: session,
                reading: LoggablePressSource(focus: focus, history: .empty),
                restStartDate: Date(timeIntervalSinceReferenceDate: 1_000),
                restEndDate: Date(timeIntervalSinceReferenceDate: 1_090)
            )
        )
    }
}
