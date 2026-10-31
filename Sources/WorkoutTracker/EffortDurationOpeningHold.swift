import Foundation

extension EffortDuration {
    /// The Opening Hold a Coach Note prescribes: the first duration a hold governs, in a clause
    /// that puts it at the start of the Set, as in `Start w/ 15 sec hold at the top`,
    /// `hold for 30 seconds`, or the `20 sec` of `Rest 60 sec hold 20 sec`. A note that names one
    /// Set, as `On the last set, hold 30 sec` does, prescribes none, because the note speaks for
    /// every Set. So does a clause that puts the hold anywhere but the start, as
    /// `2 sec hold at the bottom of each rep` or `finish with a 10 sec hold` do, and a duration
    /// no hold governs, as `rest 90 sec` or `hold at the top for 2 sec`.
    init?(openingHoldIn coachNote: String) {
        guard !coachNote.contains(NoteClause.namesOneSet),
            let hold = NoteClause.clauses(of: coachNote).lazy.compactMap(\.openingHold).first
        else { return nil }
        self = hold
    }
}

/// One clause of a Coach Note, read for the holds it writes and the part of the Set it puts them
/// in.
private struct NoteClause {
    let text: String

    /// `first set`, `top set`, `2nd set`, `last two sets`, `set 1`, `sets 1-2`.
    static var namesOneSet: Regex<Substring> {
        /\b(?:first|last|final|top|second|\d+(?:st|nd|rd|th))\s+(?:(?:two|\d+)\s+)?sets?\b|\bsets?\s+\d/.ignoresCase()
    }

    /// A pause in each rep lasts this long or less, so a hold no longer than it opens the Set only
    /// when the clause says so.
    private static let longestRepPause = 5

    /// A comma, a semicolon, a line break, or a full stop before a new sentence. The full stop of
    /// `15 sec. hold` or `1.5 min` ends nothing.
    private static var clauseEnd: Regex<Substring> { /[,;!?\n]|\.(?=\s+[A-Z])/ }

    /// Words that tie a clause to each rep, the last rep, or the time between Sets.
    private static var pastTheStart: Regex<Substring> {
        /\b(?:each|every|per|all|between|after|last|final|finish(?:es|ing)?|end(?:s|ing)?)\b/.ignoresCase()
    }

    /// A hold at the bottom is a pause in each rep, unless the clause opens the Set with it.
    private static var atTheBottom: Regex<Substring> { /\bbottom\b/.ignoresCase() }

    /// A clause about a superset speaks for the other Exercise.
    private static var superset: Regex<Substring> { /\bsuper\s*-?\s*set/.ignoresCase() }

    private static var opensTheSet: Regex<Substring> { /\b(?:start|begin)/.ignoresCase() }

    /// How a fragment that only says when or where begins, as `On the last rep` and
    /// `At the bottom` do.
    private static var frameOpener: Regex<Substring> {
        /\s*(?:on|in|at|after|during|each|every|per|between|last|final)\b/.ignoresCase()
    }

    /// The note's clauses. A fragment with no duration that only says when or where, as
    /// `Each rep,` does, belongs to the clause after it.
    static func clauses(of note: String) -> [NoteClause] {
        note.split(separator: clauseEnd).reduce(into: []) { clauses, text in
            if let frame = clauses.last, frame.isAFrame {
                clauses[clauses.count - 1] = NoteClause(text: frame.text + " " + text)
            } else {
                clauses.append(NoteClause(text: String(text)))
            }
        }
    }

    /// The clause's first hold, when the clause puts it at the start of the Set: never in a clause
    /// about each rep, the last rep, the time between Sets, or a superset, and at the bottom or as
    /// short as a rep's pause only when the clause opens the Set with it.
    var openingHold: EffortDuration? {
        guard !text.contains(Self.pastTheStart), !text.contains(Self.superset),
            let hold = EffortDuration.written(in: text).first(where: { HoldGovernor(of: $0, in: text) == .hold })?.duration
        else { return nil }
        let isARepPause = text.contains(Self.atTheBottom) || hold.seconds <= Self.longestRepPause
        return isARepPause && !text.contains(Self.opensTheSet) ? nil : hold
    }

    private var isAFrame: Bool {
        EffortDuration.written(in: text).isEmpty && text.prefixMatch(of: Self.frameOpener) != nil
    }
}

/// The word a written duration is for: a hold, or a rest, break, or pause, which is no hold.
private enum HoldGovernor: Equatable {
    case hold
    case notAHold

    private static let words: [String: HoldGovernor] = [
        "hold": .hold, "holds": .hold, "holding": .hold, "iso": .hold, "isometric": .hold,
        "rest": .notAHold, "break": .notAHold, "pause": .notAHold
    ]

    /// A governing word and what may sit between it and the duration after it: `hold for about`,
    /// `hold at least`, `Hold:`, `Hold (`, `rest ~`.
    private static var wordBefore: Regex<(Substring, word: Substring)> {
        #/\b(?<word>\p{L}+)(?:[\s:(~\-–—]|for|about|approx\.?|at\s+least|up\s+to)*$/#
    }

    /// The governing word right after a duration: `15 sec hold`, `15 sec. hold`, `15-sec hold`,
    /// `15 sec static hold`, `30-second plank hold`.
    private static var wordAfter: Regex<(Substring, word: Substring)> {
        #/[\s.\-]*(?:(?:static|plank)\s+)?(?<word>\p{L}+)/#
    }

    /// The word right before the duration governs it, so the `60 sec` of `Rest 60 sec hold 20 sec`
    /// is a rest. Failing that, the word right after does. A double prime is read only with the
    /// hold after it, because `Hold 2" off the floor` writes inches.
    init?(of written: EffortDuration.Written, in clause: String) {
        let before = written.isDoublePrime ? nil : clause[..<written.range.lowerBound].firstMatch(of: Self.wordBefore)?.word
        let after = clause[written.range.upperBound...].prefixMatch(of: Self.wordAfter)?.word
        guard let governor = before.flatMap(Self.governor) ?? after.flatMap(Self.governor) else { return nil }
        self = governor
    }

    private static func governor(_ word: Substring) -> HoldGovernor? {
        words[word.lowercased()]
    }
}
