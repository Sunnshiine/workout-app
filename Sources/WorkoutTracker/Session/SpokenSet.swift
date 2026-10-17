import Foundation

/// A Set as the athlete said it, read from a speech transcript before it meets the Set it is for:
/// some of a Set Log's values, the previous Set again, or a skip.
enum SpokenSet: Equatable, Sendable {
    /// At least one number or bodyweight is said, though the recognizer may have cut it off.
    case values(weight: SpokenValue<Weight>, reps: SpokenValue<Int>, rpe: SpokenValue<RPE>)
    case sameAgain
    case skip

    /// Why a transcript did not become a Set's outcome.
    enum Rejection: Error, Equatable, Sendable {
        /// Silence, or only filler such as "um".
        case nothingHeard
        /// A word outside the grammar, a command mixed with numbers, or a word that labels no number.
        case unrecognized
        /// Every Set Log is in pounds.
        case kilograms
        /// Numbers the recognizer ran together, as "40542" for "405 for 2": a number whose whole part
        /// has four or more digits, which no Set holds.
        case fusedNumber
        /// A number no word places, as both numbers of "185, 5"; number words in a row that make no
        /// one number, as "nine five"; "135 for 49", which may be "135 for 4 at 9"; or alternatives
        /// that disagree.
        case ambiguous
        /// A value said twice, even as the same number or once cut off: the 4 and the 8 of "135 for 4,
        /// 8 reps", or a second Set, as in "185 for 5, 185 for 5" and "185 for 5 for 5".
        case conflicting(SetLogDraft.Field)
        /// Reps outside 1 to 100 or not whole, or a weight under 5 pounds.
        case outOfRange(SetLogDraft.Field)
        /// The number heard for the RPE is not one of the ten RPE points.
        case offLadderRPE(Double)
        /// "Same again" with no earlier structured Set Log of the Exercise to repeat.
        case nothingToRepeat
    }

    /// Reads a transcript as speech-to-text writes it: digits or number words, any casing, and
    /// punctuation. A number is a value only where a word next to it or the phrase around it says
    /// which, never by its place in the transcript, and a word outside the grammar rejects the
    /// transcript rather than being skipped, because a misheard Set written to the coach's Sheet
    /// costs more than saying it again.
    static func parse(_ transcript: String) -> Result<SpokenSet, Rejection> {
        do throws(Rejection) {
            return .success(try spokenSet(in: SpokenTranscript.words(in: transcript)))
        } catch {
            return .failure(error)
        }
    }

    private static func spokenSet(in words: [String]) throws(Rejection) -> SpokenSet {
        let meaningful = words.filter { !SpokenWord($0).isFiller }
        guard !meaningful.isEmpty else { throw .nothingHeard }
        if let command = SpokenCommand.all.first(where: { !$0.triggers.isDisjoint(with: meaningful) }) {
            guard command.vocabulary.isSuperset(of: meaningful) else { throw .unrecognized }
            return command.spokenSet
        }
        return try SpokenPhrase.values(in: SpokenTokens(words.map(SpokenWord.init)).tokens)
    }
}

/// One of a Spoken Set's values.
enum SpokenValue<Value: Equatable & Sendable>: Equatable, Sendable {
    case notSaid
    case heard(Value)
    /// Said but not heard: its marker was said last and the recognizer cut off the number after it, as
    /// the RPE of "185 for 5 at" or the reps of "185 for", the recognizer cut off its half or decimal,
    /// as the RPE of "185 for 5 at 8 and a", or its number followed a misheard "at", as the RPE of
    /// "185 for 5 and 8".
    case cutOff

    /// A value not said keeps the pre-fill. A value cut off was said, so the pre-fill is not it.
    func over(_ prefilled: Value?) -> Value? {
        switch self {
        case .notSaid: prefilled
        case .heard(let value): value
        case .cutOff: nil
        }
    }
}

extension SpokenSet {
    enum Source: Equatable, Sendable {
        case top
        case alternative
    }

    struct Chosen: Equatable, Sendable {
        let spokenSet: SpokenSet
        let source: Source
    }

    /// The transcriber's top transcript first, then its alternatives, which may repeat the top. The
    /// alternatives are read only when the top is rejected, and stand in for it only when every one
    /// that reads agrees, because two readings of one Set are two different Set Logs.
    static func parse(candidates: [String]) -> Result<Chosen, Rejection> {
        guard let top = candidates.first else { return .failure(.nothingHeard) }
        return parse(top).map { Chosen(spokenSet: $0, source: .top) }
            .flatMapError { agreed(candidates.dropFirst(), else: $0) }
    }

    private static func agreed(_ alternatives: ArraySlice<String>, else rejection: Rejection) -> Result<Chosen, Rejection> {
        let readings = alternatives.compactMap { try? parse($0).get() }
        guard let reading = readings.first else { return .failure(rejection) }
        guard readings.allSatisfy({ $0 == reading }) else { return .failure(.ambiguous) }
        return .success(Chosen(spokenSet: reading, source: .alternative))
    }
}

/// What a Spoken Set does to the Set it is for.
enum SpokenSetOutcome: Equatable, Sendable {
    case log(SetLog)
    /// The values heard over the draft, with at least one still missing. Nothing is written.
    case missingValues(SetLogDraft)
    case skip

    /// Logged once every value is present, never filled in further.
    init(_ values: SetLogDraft) {
        self = values.setLog.map(Self.log) ?? .missingValues(values)
    }
}

extension SpokenSet {
    /// `draft` is what the Set's card pre-fills and `previous` is the Exercise's nearest earlier
    /// structured Set Log in the Session. A value the athlete did not say comes only from the draft,
    /// and a value cut off is missing whatever the draft holds.
    func resolved(against draft: SetLogDraft, previous: SetLog?) -> Result<SpokenSetOutcome, Rejection> {
        switch self {
        case .values(let weight, let reps, let rpe):
            .success(
                SpokenSetOutcome(SetLogDraft(weight: weight.over(draft.weight), reps: reps.over(draft.reps), rpe: rpe.over(draft.rpe)))
            )
        case .sameAgain: previous.map { .success(.log($0)) } ?? .failure(.nothingToRepeat)
        case .skip: .success(.skip)
        }
    }
}
