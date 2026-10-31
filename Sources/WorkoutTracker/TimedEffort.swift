/// The one effort a Set's card counts down: the Opening Hold its Exercise's Coach Note prescribes,
/// else the duration of a Timed Set, else none. A Set holds at most one, so the card offers one
/// control and never asks which.
enum TimedEffort: Equatable, Hashable, Sendable {
    /// A hold before the Set's first rep, as `Start w/ 15 sec hold at the top` prescribes.
    case openingHold(EffortDuration)
    /// The whole Set is the duration, as a Reps cell of `40 sec` prescribes.
    case timedSet(EffortDuration)

    init?(coachNote: String?, reps: PrescribedReps) {
        if let hold = coachNote.flatMap(EffortDuration.init(openingHoldIn:)) {
            self = .openingHold(hold)
        } else if case .timed(let duration) = reps {
            self = .timedSet(duration)
        } else {
            return nil
        }
    }

    var duration: EffortDuration {
        switch self {
        case .openingHold(let duration), .timedSet(let duration): duration
        }
    }
}

extension ExerciseSet {
    /// Every Set of an Exercise whose Coach Note prescribes an Opening Hold holds it, because the
    /// note speaks for each Set.
    var timedEffort: TimedEffort? {
        TimedEffort(coachNote: exercise?.coachNote, reps: prescription.reps)
    }
}
