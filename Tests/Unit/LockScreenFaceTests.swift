import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private let nextSet = ActiveSetID(exerciseOrder: 0, setIndex: 1)

/// What the Lock Screen card's rest face draws for the Set it is on, and which faces that Set has.
@MainActor
@Suite struct LockScreenFaceTests {
    @Test func anOrdinarySetShowsItsWeightRepsAndRPEUnderTheirUnits() throws {
        let card = try content(after: exercise("3:1:1 Bench Press", next: ("5", "RPE 8")), showing: .pounds(267.5))

        #expect(card.stats.map(\.label) == ["lbs", "reps", "RPE"])
        #expect(card.stats.map(\.value) == ["267.5", "5", "8"])
        #expect(card.stats.map(\.spoken) == ["267.5 pounds", "5 Reps", "RPE 8"])
        #expect(card.stats.allSatisfy { !$0.isMissing })
    }

    @Test func aDropSetShowsTheWeightWorkedOutFromTheSetBefore() throws {
        let card = try content(after: exercise("BB RDL", next: ("8", "Drop 17.5%"), loggedAt: 300))

        #expect(card.stats.map(\.value) == ["247.5", "8", LockScreenStat.missingValue])
    }

    @Test func extremeValuesGroupTheWeightKeepTheRepsTextAndDashTheMissingRPE() throws {
        let exercise = exercise("2-3:1:0 BB RDL", next: ("AMRAP", "Start conservative and work up to a heavy single"))

        let card = try content(after: exercise, showing: .pounds(1002.5))

        #expect(card.stats.map(\.value) == ["1,002.5", "AMRAP", "—"])
        #expect(card.stats.map(\.isMissing) == [false, false, true])
        #expect(card.stats.map(\.spoken) == ["1002.5 pounds", "AMRAP Reps", "No RPE"])
        #expect(card.weightValue == "1002.5", "the Set Log keeps the bare digits")
    }

    @Test func aBodyweightSetNamesItselfWithNoUnitOverIt() throws {
        let card = try content(after: exercise("Pull-Up", next: ("8-10", "BW")), showing: .bodyweight)

        #expect(card.stats.map(\.label) == ["", "reps", "RPE"])
        #expect(card.stats.map(\.value) == ["BW", "8-10", "—"])
        #expect(card.stats.map(\.spoken) == ["Bodyweight", "8 to 10 Reps", "No RPE"])
    }

    @Test(
        arguments: [
            ("1", "reps", "1", "1 Rep"),
            ("7 – 8", "reps", "7-8", "7 to 8 Reps"),
            ("5+", "reps", "5+", "5+ Reps"),
            ("", "reps", "—", "No Reps"),
            ("40 sec", "sec", "40", "40 seconds"),
            ("25 min", "min", "25", "25 minutes"),
            ("1:30", "min", "1:30", "1 minute 30 seconds")
        ]
    )
    func theRepsReadAsTheCoachWroteThem(cell: String, label: String, value: String, spoken: String) {
        let stat = LockScreenStat.row(weight: nil, prescription: Prescription(reps: cell, load: "", percentOneRM: nil), repsCell: cell)[1]

        #expect(stat.label == label)
        #expect(stat.value == value)
        #expect(stat.spoken == spoken)
    }

    @Test func aSetWhoseCardHoldsNoWeightDashesIt() {
        let stat = LockScreenStat.row(weight: nil, prescription: Prescription(reps: "5", load: "RPE 8", percentOneRM: nil), repsCell: "5")[
            0
        ]

        #expect(stat.label == "lbs")
        #expect(stat.value == "—")
        #expect(stat.isMissing)
        #expect(stat.spoken == "No weight")
    }

    @Test func aCardComesUpOnItsRestFaceWithNothingChosen() throws {
        #expect(try content(after: exercise("Bench Press", coachNote: "Pause on the chest.")).face == .rest)
    }

    @Test func aSetWithChoicesAndACoachNoteHasEveryFace() throws {
        let card = try content(after: exercise("Bench Press", coachNote: "Pause on the chest."))

        for face in [LockScreenFace.rest, .coachNote, .reps, .rpe(reps: 1), .rpe(reps: 100)] {
            #expect(card.turned(to: face).face == face)
        }
    }

    @Test func aSetWithNoCoachNoteHasNoCoachNoteFace() throws {
        let card = try content(after: exercise("Bench Press", coachNote: "  "))

        #expect(card.turned(to: .coachNote).face == .rest)
        #expect(card.turned(to: .reps).face == .reps)
    }

    /// A Timed Set offers no chips, so it has no face to choose a Set Log on.
    @Test func aSetWithNoChoicesHasNoRepsOrRPEFace() throws {
        let card = try content(after: exercise("Plank", coachNote: "Brace.", next: ("40 sec", "BW")))

        try #require(card.press == .needsApp)
        #expect(card.turned(to: .reps).face == .rest)
        #expect(card.turned(to: .rpe(reps: 5)).face == .rest)
        #expect(card.turned(to: .coachNote).face == .coachNote)
    }

    @Test(arguments: [0, 101, -3])
    func repsNoChipCarriesTurnNoCardToRPE(reps: Int) throws {
        #expect(try content(after: exercise("Bench Press")).turned(to: .rpe(reps: reps)).face == .rest)
    }

    @Test func aCardRedrawnForTheSameSetKeepsItsFace() throws {
        let fresh = try content(after: exercise("Bench Press", coachNote: "Pause on the chest."))
        let running = fresh.turned(to: .rpe(reps: 6))

        #expect(fresh.keepingTheFace(of: running).face == .rpe(reps: 6))
    }

    @Test func aCardThatMovedToAnotherSetStartsOnItsRestFace() throws {
        let bench = exercise("Bench Press", coachNote: "Pause on the chest.")
        let running = try content(after: bench).turned(to: .coachNote)
        var moved = try content(after: bench)
        moved.target = LiveActivityRestTarget(
            session: try #require(running.target).session,
            setID: ActiveSetID(exerciseOrder: 1, setIndex: 0)
        )

        #expect(moved.keepingTheFace(of: running).face == .rest)
    }

    @Test func aCardWhoseSetLostTheFaceGoesBackToItsRestFace() throws {
        let running = try content(after: exercise("Bench Press", coachNote: "Pause on the chest.")).turned(to: .coachNote)
        let withoutTheNote = try content(after: exercise("Bench Press", coachNote: nil))

        #expect(withoutTheNote.keepingTheFace(of: running).face == .rest)
    }

    private func exercise(
        _ name: ExerciseName,
        coachNote: String? = nil,
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

    private func content(after exercise: Exercise, showing weight: Weight? = nil) throws -> LiveActivityRestContent {
        let focus = ActiveSetFocusManager(session: nil)
        if let weight {
            focus.cardShows(SetLogDraft(weight: weight, reps: nil, rpe: nil), for: nextSet)
        }
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
