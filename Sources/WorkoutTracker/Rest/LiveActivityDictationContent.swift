import Foundation

/// What the Live Activity shows of a Dictation the athlete ran without opening the app: where it
/// stands, over the Set it is about.
struct LiveActivityDictationContent: Equatable, Sendable {
    /// Read on the Lock Screen in place of the card.
    enum Readback: Equatable, Sendable {
        case listening
        /// The Set Log written, as "235×5 @7", and the Set it went to.
        case logged(String, to: WrittenSet)
        case skipped(WrittenSet)
        /// Why nothing was written, in the card's words.
        case notLogged(String)
    }

    /// The Set a write went to, named apart from the rest it began, which leads to another.
    struct WrittenSet: Equatable, Sendable {
        let exerciseName: String
        /// The Set's place among its Exercise's Sets, from 1, as its card numbers it.
        let setOrdinal: Int
        let setsTotal: Int
        /// The Set as a rest names the Set it leads to.
        let target: LiveActivityRestTarget?
    }

    /// The Set listened for, or the rest a logged Set began toward the next one.
    enum Subject: Equatable, Sendable {
        case set(LiveActivitySetContent)
        case rest(LiveActivityRestContent)
    }

    let readback: Readback
    let subject: Subject
}

extension LiveActivityDictationContent {
    /// Whether this readback sits over a rest the stage already runs, keeping its countdown. A
    /// rest this content carries replaces it, and a write uses up a rest that led to the Set it
    /// wrote, which the card's reconcile ends once that Set is no longer Pending.
    func rides(_ rest: LiveActivityRestContent) -> Bool {
        guard case .set = subject else { return false }
        guard let written = readback.writtenSet else { return true }
        return rest.target != written.target
    }
}

extension LiveActivityDictationContent.Readback {
    var writtenSet: LiveActivityDictationContent.WrittenSet? {
        switch self {
        case .logged(_, let set), .skipped(let set): set
        case .listening, .notLogged: nil
        }
    }
}

extension LiveActivityDictationContent.WrittenSet {
    @MainActor
    init(_ position: SessionSetPosition, in session: Session) {
        let sets = SessionSetOrder.orderedSets(in: [position.exercise])
        self.init(
            exerciseName: position.exercise.exerciseName.base,
            setOrdinal: (sets.firstIndex { $0.set === position.set } ?? position.set.index) + 1,
            setsTotal: sets.count,
            target: session.placement.coordinate.map { LiveActivityRestTarget(session: $0, setID: position.setID) }
        )
    }
}

/// What the Live Activity says when the athlete asked to log a Set and there was none to listen
/// for, so the press never reads as doing nothing.
enum LiveActivityNoSetReadback: Equatable, Sendable {
    /// The Current Session, by its Live Activity label, has no Pending Set: each is logged or skipped.
    case noSetLeft(session: String)
    /// No Sheet is chosen, or the Block it loaded has no Session to log into.
    case noCurrentSession
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
        exerciseName = position.exercise.exerciseName.base
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
