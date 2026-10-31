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
        /// A word outside the grammar, or a word that labels no number.
        case unrecognized
        /// Every Set Log is in pounds.
        case kilograms
        /// Numbers the recognizer ran together: a number of 1,000 or more that may hide another value,
        /// as "40542" for "405 for 2" and "1358 at 9" for "135 for 8 at 9", or a leading number no word
        /// labels that ends in 4, as "84 5 reps at 8" for "80 for 5 reps at 8".
        case fusedNumber
        /// A number no word places, as both numbers of "185, 5"; number words in a row that make no
        /// one number, as "nine five"; "135 for 49", which may be "135 for 4 at 9"; "or", a choice; a
        /// command that names a Set or a Session, as "skip set one" or "same as last time"; or
        /// alternatives that disagree.
        case ambiguous
        /// A value said twice, even as the same number or once cut off: the 4 and the 8 of "135 for 4,
        /// 8 reps", or a second Set, as in "185 for 5, 185 for 5" and "185 for 5 for 5".
        case conflicting(SetLogDraft.Field)
        /// Reps not whole or 0, as "135 for 8.5", or a weight of 0 pounds.
        case outOfRange(SetLogDraft.Field)
        /// A value said that no lifter logs, so the transcript is more likely misheard than true:
        /// more than 100 reps, or a weight finer than a quarter pound, as "12.47" for "1247".
        case implausible(SetLogDraft.Field)
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
            return try command.read(meaningful)
        }
        return try SpokenPhrase.values(in: SpokenTokens(words.map(SpokenWord.init)).tokens)
    }
}

/// One of a Spoken Set's values.
enum SpokenValue<Value: SpokenQuantity>: Equatable, Sendable {
    case notSaid
    case heard(Value)
    /// Said but not heard: its marker was said last and the recognizer cut off the number after it, as
    /// the RPE of "185 for 5 at" or the reps of "185 for", the recognizer cut off its half or decimal,
    /// as the RPE of "185 for 5 at 8 and a", or its number followed a misheard "at", as the RPE of
    /// "185 for 5 and 8".
    case cutOff(SpokenRemnant)

    /// A value not said keeps the pre-fill. A value cut off was said, so the pre-fill is not it.
    func over(_ prefilled: Value?) -> Value? {
        switch self {
        case .notSaid: prefilled
        case .heard(let value): value
        case .cutOff: nil
        }
    }

    var isCutOff: Bool {
        guard case .cutOff = self else { return false }
        return true
    }

    /// Whether `other` hears this value: the same value, or any one heard where this was cut off.
    func isHeard(by other: SpokenValue<Value>) -> Bool {
        switch (self, other) {
        case (.cutOff, .heard): true
        case (.cutOff, _): false
        default: self == other
        }
    }

    /// Whether `other` is this value as the recognizer heard it: the value itself, or, where this was
    /// cut off, one heard that the remnant left in its place admits.
    func admits(_ other: SpokenValue<Value>) -> Bool {
        switch (self, other) {
        case (.cutOff(let remnant), .heard(let value)): remnant.admits(value.spokenNumber)
        default: self == other
        }
    }
}

/// What the recognizer wrote where it cut a value off.
enum SpokenRemnant: Equatable, Sendable {
    /// Nothing, as after the "at" of "185 for 5 at".
    case nothing
    /// The number after a misheard "at", as the 8 of "185 for 5 and 8".
    case number(Double)
    /// A number whose half or decimal was cut off, as the 8 of "at 8 and a".
    case wholePart(Double)

    /// Whether the value said may be `number`, nil for bodyweight: anything where nothing was heard,
    /// and otherwise only a number that agrees with the one heard.
    func admits(_ number: Double?) -> Bool {
        switch self {
        case .nothing: true
        case .number(let heard): number == heard
        case .wholePart(let whole): number.map { $0 > whole && $0 < whole + 1 } ?? false
        }
    }
}

/// A value of a Set Log, as the number that says it.
protocol SpokenQuantity: Equatable, Sendable {
    /// nil for a value no number says, as bodyweight.
    var spokenNumber: Double? { get }
}

extension Weight: SpokenQuantity {
    var spokenNumber: Double? {
        guard case .pounds(let pounds) = self else { return nil }
        return pounds
    }
}

extension Int: SpokenQuantity {
    var spokenNumber: Double? { Double(self) }
}

extension RPE: SpokenQuantity {
    var spokenNumber: Double? { rawValue }
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
    /// top is read with the words its alternatives heard where it lost them, and a value it cut off
    /// is settled by its alternatives when every one that hears the same Set hears that value the
    /// same, and that value is the number the top heard in its place, if the top heard one. Otherwise
    /// the alternatives are read only when the top is rejected, and stand in for it only when every
    /// one that reads agrees, because two readings of one Set are two different Set Logs.
    static func parse(candidates: [String]) -> Result<Chosen, Rejection> {
        guard let top = candidates.first else { return .failure(.nothingHeard) }
        let alternatives = candidates.dropFirst()
        return parse(top, restoringWhatItLostFrom: alternatives).map { Chosen(spokenSet: $0.settled(by: alternatives), source: .top) }
            .flatMapError { agreed(alternatives, else: $0) }
    }

    /// The top transcript as read, unless the recognizer lost words of what was said. An alternative
    /// that is the top with words before it, as "10 for 12 at 8" is "for 12 at 8", heard the start
    /// the top cut off, and where the top is ambiguous, as a number no word places makes it, one that
    /// is the top with only "at" added, as "275 for 4 at 9" is "275 for 4 9", heard the "at" the top
    /// lost: those alternatives read the Set when every one that reads agrees. One whose first number
    /// is longer and ends in the top's, as "225 for 3 add 8" beside "25 for 3 add 8", either heard the
    /// start of that number or misheard it, as "18" for "eight", so the top is ambiguous.
    private static func parse(_ top: String, restoringWhatItLostFrom alternatives: ArraySlice<String>) -> Result<SpokenSet, Rejection> {
        let words = SpokenTranscript.words(in: top)
        guard words.contains(where: { !SpokenWord($0).isFiller }) else { return parse(top) }
        let heard = alternatives.map(SpokenTranscript.words(in:))
        guard !heard.contains(where: { startsWithALongerNumber($0, endingInTheFirstOf: words) }) else { return .failure(.ambiguous) }
        let restored = heard.filter { $0.count > words.count && $0.suffix(words.count).elementsEqual(words) }
        return agreedReading(of: restored) ?? parse(top).flatMapError { restoringAnAt(words, from: heard, else: $0) }
    }

    private static func restoringAnAt(
        _ words: [String],
        from heard: [[String]],
        else rejection: Rejection
    ) -> Result<SpokenSet, Rejection> {
        guard rejection == .ambiguous else { return .failure(rejection) }
        return agreedReading(of: heard.filter { addsOnlyAt($0, to: words) }) ?? .failure(rejection)
    }

    private static func agreedReading(of heard: [[String]]) -> Result<SpokenSet, Rejection>? {
        let readings = heard.compactMap { try? spokenSet(in: $0) }
        guard let reading = readings.first else { return nil }
        return readings.allSatisfy { $0 == reading } ? .success(reading) : .failure(.ambiguous)
    }

    /// Only "at", because the recognizer drops it between the reps and the RPE: a "reps" added to "135
    /// for 49" would read the 49 that may be "4 at 9" as reps.
    private static func addsOnlyAt(_ alternative: [String], to words: [String]) -> Bool {
        guard alternative.count > words.count else { return false }
        var rest = words[...]
        for word in alternative {
            guard word != rest.first else {
                rest.removeFirst()
                continue
            }
            guard SpokenWord(word) == .token(.marker(.at)) else { return false }
        }
        return rest.isEmpty
    }

    private static func startsWithALongerNumber(_ alternative: [String], endingInTheFirstOf words: [String]) -> Bool {
        guard let number = alternative.first, let top = words.first, (number + top).allSatisfy(\.isNumber) else { return false }
        return number.count > top.count && number.hasSuffix(top)
    }

    /// This Set with the value the recognizer cut off heard from the alternatives that hear every
    /// other value as the top did, when they all hear it the same and it is the number the top heard
    /// in its place. The recognizer writes "and" or "add" for "at" in a top transcript and "at" in an
    /// alternative, so the RPE of "185 for 5 and 8" is the 8 of "185 for 5 at 8", never the 7 of
    /// "185 for 5 at 7". Alternatives that hear two RPEs settle nothing.
    private func settled(by alternatives: ArraySlice<String>) -> SpokenSet {
        guard hasACutOffValue else { return self }
        let settling = alternatives.compactMap { try? Self.parse($0).get() }.filter(isHeard(by:))
        guard let settled = settling.first, settling.allSatisfy({ $0 == settled }), admits(settled) else { return self }
        return settled
    }

    private var hasACutOffValue: Bool {
        guard case .values(let weight, let reps, let rpe) = self else { return false }
        return weight.isCutOff || reps.isCutOff || rpe.isCutOff
    }

    /// Whether `other` hears every value of this Set as it was heard, and the one cut off.
    private func isHeard(by other: SpokenSet) -> Bool {
        guard case .values(let weight, let reps, let rpe) = self, case .values(let otherWeight, let otherReps, let otherRPE) = other
        else { return false }
        return weight.isHeard(by: otherWeight) && reps.isHeard(by: otherReps) && rpe.isHeard(by: otherRPE)
    }

    private func admits(_ other: SpokenSet) -> Bool {
        guard case .values(let weight, let reps, let rpe) = self, case .values(let otherWeight, let otherReps, let otherRPE) = other
        else { return false }
        return weight.admits(otherWeight) && reps.admits(otherReps) && rpe.admits(otherRPE)
    }

    private static func agreed(_ alternatives: ArraySlice<String>, else rejection: Rejection) -> Result<Chosen, Rejection> {
        let reading = agreedReading(of: alternatives.map(SpokenTranscript.words(in:))) ?? .failure(rejection)
        return reading.map { Chosen(spokenSet: $0, source: .alternative) }
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
