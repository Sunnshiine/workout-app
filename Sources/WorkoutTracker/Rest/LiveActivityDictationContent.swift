import Foundation

/// What the Live Activity shows of a Dictation the athlete ran without opening the app: where it
/// stands, over the Set it is about.
struct LiveActivityDictationContent: Equatable, Sendable {
    /// Read on the Lock Screen in place of the card.
    enum Readback: Equatable, Sendable {
        case listening
        /// The Set Log written, as "235×5 @7".
        case logged(String)
        case skipped
        /// Why nothing was written, in the card's words.
        case notLogged(String)
    }

    /// The Set listened for, or the rest a logged Set began toward the next one.
    enum Subject: Equatable, Sendable {
        case set(LiveActivitySetContent)
        case rest(LiveActivityRestContent)
    }

    let readback: Readback
    let subject: Subject
}

/// A Set with no rest running: what the Live Activity shows while a headless Dictation listens
/// for it, and when nothing was written.
struct LiveActivitySetContent: Equatable, Sendable {
    let exerciseName: String
    let prescribedReps: String
    let prescribedLoad: String
    let setsDone: Int
    let setsTotal: Int

    @MainActor
    init(_ position: SessionSetPosition) {
        exerciseName = position.exercise.name
        prescribedReps = position.set.prescribedReps
        prescribedLoad = position.set.prescribedLoad
        setsTotal = position.exercise.sets.count
        setsDone = max(setsTotal - position.exercise.pendingSetCount, 0)
    }
}

extension SetLog {
    /// The Set Log as the Lock Screen reads it back.
    var readback: String {
        "\(weight.label)×\(reps) @\(rpe.label)"
    }
}
