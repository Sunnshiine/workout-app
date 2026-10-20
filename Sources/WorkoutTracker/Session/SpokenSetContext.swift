import Foundation

/// What the Spoken Set for one Set resolves against.
struct SpokenSetContext: Equatable, Sendable {
    /// Which Set this is, for the press's Dictation Record. Nil for a Set the Block no longer holds.
    let set: DictatedSet?
    /// What the Set's card shows, which fills what the athlete leaves unsaid.
    let draft: SetLogDraft
    /// The Exercise's nearest earlier structured Set Log in the Session, which "same again" logs.
    let previous: SetLog?
}

extension SpokenSetContext {
    /// A Set as its card first shows it.
    @MainActor
    init(for set: ExerciseSet, history: LastPerformedLookupSnapshot) {
        self.init(for: set, showing: SetLogDraft(prefilling: set, suggestion: LoadSuggestionEngine.suggest(for: set, history: history)))
    }

    /// A Set whose card shows `draft`, which the athlete may have changed.
    @MainActor
    init(for set: ExerciseSet, showing draft: SetLogDraft) {
        self.init(set: DictatedSet(set), draft: draft, previous: set.earlierSetLogs.first?.setLog)
    }

    /// What a Spoken Set for `set` resolves against on every path, the card's mic or a press with
    /// the phone locked: what the card shows for `set` once it has reported it, the card's first
    /// values otherwise.
    @MainActor
    init(for set: ExerciseSet, shownBy focus: ActiveSetFocusManager, history: LastPerformedLookupSnapshot) {
        if let setID = ActiveSetFocusManager.id(for: set), let draft = focus.cardDraft(for: setID) {
            self.init(for: set, showing: draft)
        } else {
            self.init(for: set, history: history)
        }
    }
}

/// Which Set a press was for, in the terms that find it again after a reload.
struct DictatedSet: Equatable, Sendable {
    let block: String
    let address: SetAddress
    let exercise: String
}

extension DictatedSet {
    @MainActor
    init?(_ set: ExerciseSet) {
        guard let exercise = set.exercise, let session = exercise.session, let week = session.week, let block = week.block else {
            return nil
        }
        let address = ExerciseAddress(session: week.address(of: session), order: exercise.order)
        self.init(block: block.tabName, address: SetAddress(exercise: address, index: set.index), exercise: exercise.exerciseName.entered)
    }
}
