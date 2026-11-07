import Foundation

extension SetFlagStanding {
    /// What the athlete reads beside the flag, in the language of Saved and the sync status. Only a
    /// refusal names the flag, because its danger mark does not.
    var word: String {
        switch self {
        case .refused: "Flag not written"
        case .unsynced: "Unsynced"
        case .landed: "In the Sheet"
        }
    }
}

/// What the athlete has chosen so far in the Set Flag sheet. Words stay on one line and inside what a
/// flag can carry as they are typed, so the only flag this cannot make is one still missing something.
/// Words typed before a kind choose Other, so typing first never ends at a capsule that will not press.
struct SetFlagDraft: Equatable, Sendable {
    var kind: SetFlagKind?
    var words: String {
        didSet {
            words = String(String(words.map { $0.isNewline ? " " : $0 }).prefix(SetFlag.maximumTextLength))
            if kind == nil, !words.allSatisfy(\.isWhitespace) { kind = .other }
        }
    }

    init() {
        kind = nil
        words = ""
    }

    var flag: SetFlag? {
        kind.flatMap { SetFlag(kind: $0, text: words) }
    }

    var placeholder: String {
        kind == .other ? "Other needs a few words" : "What should your coach know?"
    }
}

/// The Set Flag sheet's facts about one Set, read fresh each time so a flush or a sync shows through.
struct SetFlagSheetPresentation: Identifiable, Equatable {
    struct RaisedFlag: Identifiable, Equatable {
        let sentence: String
        let standing: SetFlagStanding

        var id: String { sentence }

        init(_ entry: SetFlagEntry) {
            let label = entry.flag.kind.label
            sentence = entry.flag.text.map { "\(label): \($0)" } ?? label
            standing = entry.standing
        }
    }

    let id: SetCoordinates.ID
    let exerciseName: String
    /// The Set the flag lands on and what it holds: `Set 2 · 185x5@8`, or `Set 2` for a Pending Set.
    let setLine: String
    let raiseTitle: String
    /// Newest first, so the flag the athlete is most likely checking on leads the list.
    let raisedFlags: [RaisedFlag]

    @MainActor
    init(id: SetCoordinates.ID, set: ExerciseSet) {
        let setName = "Set \(set.index + 1)"
        self.id = id
        exerciseName = set.exercise?.exerciseName.base ?? ""
        setLine = Self.written(on: set).map { "\(setName) · \($0)" } ?? setName
        raiseTitle = "Flag \(setName)"
        raisedFlags = set.setFlags.reversed().map(RaisedFlag.init)
    }

    /// The sheet's first height has room for the kinds and the capsule alone, so a Set with raised flags
    /// opens tall, where the athlete can read where each one stands.
    var opensTall: Bool {
        !raisedFlags.isEmpty
    }

    @MainActor
    private static func written(on set: ExerciseSet) -> String? {
        switch set.state {
        case .logged: set.setLog?.formatted ?? set.displayReps
        case .skipped: "Skipped"
        case .pending: nil
        }
    }
}
