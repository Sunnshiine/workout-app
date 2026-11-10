import Foundation

@testable import WorkoutTracker

/// A Set as the Lock Screen card gets it, from the cells its Exercise holds in the Sheet. The rest
/// is long over, so the countdown reads a stable `Ready`.
struct LockScreenCardSet: Sendable {
    static let cadence = "3:1:1"
    static let coachNote = "Brace hard off the floor, controlled descent."

    var exerciseName = "Back Squat"
    var reps = "5"
    var load = "RPE7"
    var weight: Weight? = .pounds(252.5)
    var cadence: String? = LockScreenCardSet.cadence
    var coachNote: String? = LockScreenCardSet.coachNote
    var press = LoggablePress.ready(offer(reps: [3, 4, 5, 6, 7], prescribed: [5], rpe: "7"))
    var start: LockScreenStartOffer?
    var pendingWrites = 0
    var setsDone = 1
    var restEnd: Date? = Date(timeIntervalSinceReferenceDate: 1_000)

    static let backSquat = LockScreenCardSet()
    static let noCoachNote = LockScreenCardSet(coachNote: nil)
    static let noCadence = LockScreenCardSet(cadence: nil)
    static let neitherCadenceNorCoachNote = LockScreenCardSet(cadence: nil, coachNote: nil)

    /// The issue's worst case: a weight in the thousands, AMRAP, no RPE, a range Cadence, a long note.
    static let worstCase = LockScreenCardSet(
        exerciseName: "Paused Low-Bar Competition Back Squat w/ Safety Squat Bar",
        reps: "AMRAP",
        load: "Start conservative and work up to a heavy single",
        weight: .pounds(1002.5),
        cadence: "2-3:1:0",
        coachNote: "Belt off, knee wraps on. Stop the Set the moment the bar speed drops off at all, and note how far it slowed",
        press: .ready(offer(reps: [8, 9, 10, 11, 12], prescribed: [], rpe: nil, choices: ["8", "8.5", "9", "9.5", "10"]))
    )

    static let bodyweight = LockScreenCardSet(
        exerciseName: "Pull-Up",
        reps: "12",
        load: "BW",
        weight: .bodyweight,
        press: .ready(offer(reps: [10, 11, 12, 13, 14], prescribed: [12], rpe: nil))
    )

    /// A Drop Set with nothing performed before it, which has no weight for the card to log.
    static let noWeight = LockScreenCardSet(exerciseName: "BB RDL", reps: "8", load: "Drop 17.5%", weight: nil, press: .needsApp)

    /// The Exercise's Coach Note opens each Set on a hold, so the Start takes the mic's place.
    static let openingHold = LockScreenCardSet(
        exerciseName: "BB RDL",
        reps: "8-10",
        load: "RPE 8-9",
        weight: .pounds(185),
        cadence: "2-3:1:0",
        coachNote: "Start w/ 10 sec hold, proceed to rep range.",
        press: .ready(offer(reps: [6, 7, 8, 9, 10], prescribed: [8, 9, 10], rpe: nil)),
        start: LockScreenStartOffer(
            label: "10 s hold",
            spokenLabel: "10 second hold",
            url: AppEntryRequest.startTimedEffort(
                CountdownRun.Owner(
                    session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
                    set: ActiveSetID(exerciseOrder: 2, setIndex: 0)
                )
            ).url
        )
    )

    static func offer(
        reps: [Int],
        prescribed: [Int],
        rpe: String?,
        choices: [String] = ["6", "6.5", "7", "7.5", "8"]
    ) -> LoggablePress.Offer {
        LoggablePress.Offer(repChoices: reps, prescribedReps: prescribed, rpeChoices: choices, prescribedRPE: rpe, setIdentity: "visual")
    }

    /// The numbers are the ones the app words for these cells, so a baseline never shows a row the
    /// library would not send.
    func state(
        _ appearance: LiveActivityAppearance,
        face: LockScreenCardFace = .rest,
        dictation: LiveActivityDictation? = nil
    ) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: exerciseName,
            prescribedReps: reps,
            prescribedLoad: load,
            weightValue: weight?.label ?? "",
            weightUnit: weight?.unitLabel ?? "",
            setsDone: setsDone,
            setsTotal: 3,
            variant: .restTimerSetsLeft,
            appearance: appearance,
            restStartDate: restEnd?.addingTimeInterval(-120),
            restEndDate: restEnd,
            dictation: dictation,
            loggablePress: press,
            face: face,
            stats: LockScreenStat.row(
                weight: weight,
                prescription: Prescription(reps: reps, load: load, percentOneRM: nil),
                repsCell: reps
            )
            .map(LockScreenCardStat.init),
            cadence: cadence,
            coachNote: coachNote,
            start: start,
            pendingWrites: pendingWrites
        )
    }
}
