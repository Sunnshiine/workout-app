/// Which Exercise of a Session a Set belongs to, as the Sheet addresses it: its Entered Name and
/// how many Exercises above it in the Session share that name. The name alone is not enough, because
/// a coach can name a top single and its back-off Sets both `Back Squat` (#813).
struct ExerciseReference: Hashable, Sendable {
    let name: ExerciseName
    let ordinal: Int

    /// The Exercise as a conflict names it: numbered past the first of its name, so a missing second
    /// `Back Squat` is not reported as a missing `Back Squat` while the first is still there.
    var label: String {
        ordinal == 0 ? name.entered : "\(name.entered) number \(ordinal + 1)"
    }
}

extension Exercise {
    /// Counts by `order`, the Sheet's top-to-bottom order, which the Sheet layout's Exercise anchors
    /// follow too.
    @MainActor
    func reference(in session: Session) -> ExerciseReference {
        ExerciseReference(
            name: exerciseName,
            ordinal: session.exercises.count { $0.exerciseName == exerciseName && $0.order < order }
        )
    }
}
