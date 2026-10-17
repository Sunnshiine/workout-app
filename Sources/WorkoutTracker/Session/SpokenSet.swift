import Foundation

/// A Set as the athlete said it, read from a speech transcript before it meets the Set it is for:
/// some of a Set Log's values, the previous Set again, or a skip.
enum SpokenSet: Equatable, Sendable {
    /// At least one value is present.
    case values(SetLogDraft)
    case sameAgain
    case skip

    /// Why a transcript did not become a Set's outcome.
    enum Rejection: Error, Equatable, Sendable {
        /// Silence, or only filler such as "um".
        case nothingHeard
        /// Words outside the grammar, a command mixed with numbers, or more numbers than a Set has.
        case unrecognized
        /// Every Set Log is in pounds.
        case kilograms
        /// Numbers the recognizer ran together, as "40542" for "405 for 2": a whole number of four or
        /// more digits, which no Set holds.
        case fusedNumber
        /// Two readings: "135 for 49" may be "135 for 4 at 9", and alternatives may disagree.
        case ambiguous
        /// Two different numbers for one value: the 4 and the 8 of "135 for 4, 8 reps".
        case conflicting(SetLogDraft.Field)
        /// Reps outside 1 to 100 or not whole, or a weight outside 0 to 2000 pounds.
        case outOfRange(SetLogDraft.Field)
        /// The number heard for the RPE is not one of the ten RPE points.
        case offLadderRPE(Double)
        /// "Same again" with no earlier structured Set Log of the Exercise to repeat.
        case nothingToRepeat
    }

    /// Reads a transcript as speech-to-text writes it: digits or number words, any casing, and
    /// punctuation. A word outside the grammar rejects the transcript rather than being skipped,
    /// because a misheard Set written to the coach's Sheet costs more than saying it again.
    static func parse(_ transcript: String) -> Result<SpokenSet, Rejection> {
        do throws(Rejection) {
            return .success(try spokenSet(in: Transcript.words(in: transcript)))
        } catch {
            return .failure(error)
        }
    }

    private static func spokenSet(in words: [String]) throws(Rejection) -> SpokenSet {
        let meaningful = words.filter { !Lexicon.fillers.contains($0) }
        guard !meaningful.isEmpty else { throw .nothingHeard }
        guard Lexicon.kilograms.isDisjoint(with: meaningful) else { throw .kilograms }
        if let command = Command.all.first(where: { !$0.triggers.isDisjoint(with: meaningful) }) {
            guard command.vocabulary.isSuperset(of: meaningful) else { throw .unrecognized }
            return command.spokenSet
        }
        return .values(try values(in: words))
    }

    /// "4 at 9" can reach the transcript as "49", so a two-digit rep count said last after "for",
    /// with no RPE, whose second digit is an RPE point reads two ways. "49 reps" reads one way.
    private static func values(in words: [String]) throws(Rejection) -> SetLogDraft {
        let lexemes = try Lexemes(words[...]).lexemes
        let values = try Slots(Claims(lexemes)).draft()
        guard values.rpe == nil, let reps = values.reps, couldBeRepsAtAnRPE(reps),
            lexemes.suffix(2).elementsEqual([.marker(.by), .value(.number(Double(reps)))])
        else { return values }
        throw .ambiguous
    }

    private static func couldBeRepsAtAnRPE(_ reps: Int) -> Bool {
        (10...99).contains(reps) && RPE(rawValue: Double(reps % 10)) != nil
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
    /// structured Set Log in the Session. A value the athlete did not say comes only from the draft.
    func resolved(against draft: SetLogDraft, previous: SetLog?) -> Result<SpokenSetOutcome, Rejection> {
        switch self {
        case .values(let spoken): .success(SpokenSetOutcome(draft.overridden(by: spoken)))
        case .sameAgain: previous.map { .success(.log($0)) } ?? .failure(.nothingToRepeat)
        case .skip: .success(.skip)
        }
    }
}

/// Same again and skip, each recognized by a trigger word and allowed only its own vocabulary.
/// Read before any number, because "skip this one" holds the number word "one".
private struct Command {
    let triggers: Set<String>
    let vocabulary: Set<String>
    let spokenSet: SpokenSet

    /// What the athlete says, which happens to spell the Set Log wire token. A spoken skip reaches
    /// the Sheet through `WorkoutStore.skip`, so the word and the token change independently.
    static let spokenSkipWord = "skip"

    static let all = [
        Command(
            triggers: [spokenSkipWord],
            vocabulary: [spokenSkipWord, "it", "this", "that", "set", "one"],
            spokenSet: .skip
        ),
        Command(
            triggers: ["same", "again", "repeat"],
            vocabulary: ["same", "again", "repeat", "as", "last", "time", "set", "one", "that", "it", "previous"],
            spokenSet: .sameAgain
        )
    ]
}

private enum Transcript {
    /// Lowercased words, digit runs, a written "1/2", and `@`, with punctuation dropped and
    /// spelled-out abbreviations ("r p e", "b w", "body weight") joined into one word. A pound sign
    /// is the "pounds" after its number, and a clock time is the number its digits spell ("1:35").
    static func words(in transcript: String) -> [String] {
        let tokens = transcript.lowercased()
            .replacing("×", with: " x ")
            .replacing(/['’]/, with: "")
            .replacing(/£\s*(\d+(?:\.\d+)?)/) { "\($0.1) pounds" }
            .replacing(/(\d{1,2}):(\d{2})/) { "\($0.1)\($0.2)" }
            .matches(of: /1\/2|\d+(?:\.\d+)?|bw(?=x)|[a-z]+|@/)
            .map { String($0.output) }
        return joiningPhrases(tokens)
    }

    private static let phrases: [(words: [String], word: String)] = [
        (["r", "p", "e"], "rpe"), (["r", "p"], "rpe"), (["b", "w"], "bw"), (["body", "weight"], "bw"), (["k", "g"], "kg")
    ]

    private static func joiningPhrases(_ tokens: [String]) -> [String] {
        var words: [String] = []
        var rest = tokens[...]
        while let first = rest.first {
            let phrase = phrases.first { rest.starts(with: $0.words) }
            words.append(phrase?.word ?? first)
            rest = rest.dropFirst(phrase?.words.count ?? 1)
        }
        return words
    }
}

private enum Lexicon {
    static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "er", "erm", "ah", "oh", "hmm", "mm", "okay", "ok", "so", "the", "a", "and", "of", "with",
        "i", "did", "got", "just", "then"
    ]

    static let kilograms: Set<String> = ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"]

    static let lexemes: [String: Lexeme] = [
        "bw": .value(.bodyweight), "bodyweight": .value(.bodyweight),
        "pound": .marker(.pounds), "pounds": .marker(.pounds), "lb": .marker(.pounds), "lbs": .marker(.pounds),
        "rep": .marker(.reps), "reps": .marker(.reps),
        "rpe": .marker(.rpe), "rp": .marker(.rpe), "@": .marker(.rpe),
        "rte": .marker(.rpe), "rtd": .marker(.rpe), "rtv": .marker(.rpe),
        "at": .marker(.at),
        "for": .marker(.by), "x": .marker(.by), "by": .marker(.by), "times": .marker(.by)
    ]
}

private enum Lexeme: Equatable {
    case value(Value)
    case marker(Marker)

    var asksForTheNumberAfter: Bool {
        guard case .marker(let marker) = self else { return false }
        return marker.asksForTheNumberAfter
    }
}

private enum Value: Equatable {
    case number(Double)
    case bodyweight

    /// "at 9" is an RPE. Past the top of the ten-point scale, as in "8 reps at 135", "at" names the weight.
    var fieldAfterAt: SetLogDraft.Field {
        guard case .number(let number) = self, number <= RPE.ten.rawValue else { return .weight }
        return .rpe
    }
}

private enum Marker: Equatable {
    case pounds
    case reps
    case rpe
    case at
    /// "for", "x", "by", or "times": weight before it, reps after it.
    case by

    /// The field this marker gives the value right before it: "135 pounds", "8 reps", the 135 of "135 for 8".
    var fieldBefore: SetLogDraft.Field? {
        switch self {
        case .pounds, .by: .weight
        case .reps: .reps
        case .rpe, .at: nil
        }
    }

    /// The field this marker gives the value right after it: "RPE 9", the 8 of "135 for 8".
    func field(after value: Value) -> SetLogDraft.Field? {
        switch self {
        case .rpe: .rpe
        case .by: .reps
        case .at: value.fieldAfterAt
        case .pounds, .reps: nil
        }
    }

    var asksForTheNumberAfter: Bool {
        switch self {
        case .rpe, .at, .by: true
        case .pounds, .reps: false
        }
    }
}

/// The transcript's words read into numbers, bodyweight, and the markers that label them.
private struct Lexemes {
    private(set) var lexemes: [Lexeme] = []

    init(_ words: ArraySlice<String>) throws(SpokenSet.Rejection) {
        var rest = words
        while let word = rest.first {
            rest = try read(word, rest)
        }
    }

    private mutating func read(_ word: String, _ words: ArraySlice<String>) throws(SpokenSet.Rejection) -> ArraySlice<String> {
        if let homophone = homophone(word, before: words.dropFirst()) {
            lexemes.append(homophone)
        } else if let number = SpokenNumber.read(words) {
            guard word.wholeMatch(of: /\d{4,}/) == nil else { throw .fusedNumber }
            lexemes.append(.value(.number(number.value)))
            return number.rest
        } else if let lexeme = Lexicon.lexemes[word] {
            lexemes.append(lexeme)
        } else {
            guard Lexicon.fillers.contains(word) else { throw .unrecognized }
        }
        return words.dropFirst()
    }

    /// "four", "per", and "or" between a value and a number are the "for" of "135 four 5". "to" and
    /// "too" are 2 only where a number is asked for: "315 for to", "to reps". "and", "of", and "add"
    /// before the last number are the "at" of "185 for 5 and 8".
    private func homophone(_ word: String, before next: ArraySlice<String>) -> Lexeme? {
        switch word {
        case "four", "per", "or": theFor(before: next)
        case "to", "too": theTwo(before: next)
        case "and", "of", "add": Self.theAt(before: next)
        default: nil
        }
    }

    private var asksForANumber: Bool { lexemes.last?.asksForTheNumberAfter ?? false }

    private func theFor(before next: ArraySlice<String>) -> Lexeme? {
        guard !lexemes.isEmpty, !asksForANumber, SpokenNumber.read(next) != nil else { return nil }
        return .marker(.by)
    }

    private func theTwo(before next: ArraySlice<String>) -> Lexeme? {
        guard asksForANumber || Self.labelsTheNumberBefore(next) else { return nil }
        return .value(.number(2))
    }

    private static func theAt(before next: ArraySlice<String>) -> Lexeme? {
        guard let number = SpokenNumber.read(next),
            !number.rest.indices.contains(where: { SpokenNumber.read(number.rest[$0...]) != nil })
        else { return nil }
        return .marker(.at)
    }

    private static func labelsTheNumberBefore(_ words: ArraySlice<String>) -> Bool {
        guard let next = words.first, case .marker(let marker) = Lexicon.lexemes[next] else { return false }
        return marker.fieldBefore != nil
    }
}

/// Every number and bodyweight, with the one field the words around it name, if any.
private struct Claims {
    private(set) var labeled: [(field: SetLogDraft.Field, value: Value)] = []
    private(set) var unlabeled: [Value] = []

    init(_ lexemes: [Lexeme]) throws(SpokenSet.Rejection) {
        let previous: [Lexeme?] = [nil] + lexemes.map(Optional.some)
        let next: [Lexeme?] = lexemes.dropFirst().map(Optional.some) + [nil]
        for (lexeme, (before, after)) in zip(lexemes, zip(previous, next)) {
            guard case .value(let value) = lexeme else { continue }
            try claim(value, between: before, and: after)
        }
    }

    private mutating func claim(_ value: Value, between before: Lexeme?, and after: Lexeme?) throws(SpokenSet.Rejection) {
        let fields = Set(
            [Self.field(of: value, after: before), Self.field(before: after), value == .bodyweight ? .weight : nil].compactMap { $0 }
        )
        guard fields.count <= 1 else { throw .unrecognized }
        if let field = fields.first { labeled.append((field, value)) } else { unlabeled.append(value) }
    }

    private static func field(of value: Value, after lexeme: Lexeme?) -> SetLogDraft.Field? {
        guard case .marker(let marker) = lexeme else { return nil }
        return marker.field(after: value)
    }

    private static func field(before lexeme: Lexeme?) -> SetLogDraft.Field? {
        guard case .marker(let marker) = lexeme else { return nil }
        return marker.fieldBefore
    }
}

/// Weight, reps, and RPE as the claims fill them: labeled values first, then unlabeled ones into
/// whatever is left in weight, reps, RPE order.
private struct Slots {
    private var values: [SetLogDraft.Field: Value] = [:]

    init(_ claims: Claims) throws(SpokenSet.Rejection) {
        for (field, value) in claims.labeled { try claim(field, value) }
        try fill(claims.unlabeled)
        guard !values.isEmpty else { throw .unrecognized }
    }

    /// The same number said twice for one value, as in "135 for 8, 8 reps", is not a conflict.
    private mutating func claim(_ field: SetLogDraft.Field, _ value: Value) throws(SpokenSet.Rejection) {
        guard (values[field] ?? value) == value else { throw .conflicting(field) }
        values[field] = value
    }

    private mutating func fill(_ unlabeled: [Value]) throws(SpokenSet.Rejection) {
        let free = SetLogDraft.Field.allCases.filter { values[$0] == nil }
        guard unlabeled.count <= free.count else { throw .unrecognized }
        for (field, value) in zip(free, unlabeled) { values[field] = value }
    }

    func draft() throws(SpokenSet.Rejection) -> SetLogDraft {
        SetLogDraft(weight: try Self.weight(values[.weight]), reps: try Self.reps(values[.reps]), rpe: try Self.rpe(values[.rpe]))
    }

    private static func weight(_ value: Value?) throws(SpokenSet.Rejection) -> Weight? {
        guard case .number(let pounds) = value else { return value.map { _ in .bodyweight } }
        guard pounds > 0, pounds <= 2000 else { throw .outOfRange(.weight) }
        return .pounds(pounds)
    }

    private static func reps(_ value: Value?) throws(SpokenSet.Rejection) -> Int? {
        guard let value else { return nil }
        guard case .number(let count) = value, let reps = Int(exactly: count), (1...100).contains(reps) else {
            throw .outOfRange(.reps)
        }
        return reps
    }

    private static func rpe(_ value: Value?) throws(SpokenSet.Rejection) -> RPE? {
        guard case .number(let point) = value else { return nil }
        guard let rpe = RPE(rawValue: point) else { throw .offLadderRPE(point) }
        return rpe
    }
}

/// One number as an athlete says it: "185", "one thirty five", "a hundred and eighty five",
/// "four oh five", "eight and a half", "one eighty seven point five".
private enum SpokenNumber {
    struct Reading<Number> {
        let value: Number
        let rest: ArraySlice<String>
    }

    static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "ate": 8, "nine": 9
    ]
    static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]
    private static let multipliers = units.merging(["a": 1]) { unit, _ in unit }

    /// The number the words start with, read as far as it goes, with the words after it.
    static func read(_ words: ArraySlice<String>) -> Reading<Double>? {
        guard let whole = whole(words) else { return nil }
        let fraction = fraction(whole.rest)
        return Double(whole.value + (fraction?.value ?? "")).map { Reading(value: $0, rest: fraction?.rest ?? whole.rest) }
    }

    private static func whole(_ words: ArraySlice<String>) -> Reading<String>? {
        guard let first = words.first else { return nil }
        if first.wholeMatch(of: /\d+(?:\.\d+)?/) != nil { return Reading(value: first, rest: words.dropFirst()) }
        return (hundreds(words) ?? colloquialHundreds(words) ?? twoDigits(words)).map { Reading(value: String($0.value), rest: $0.rest) }
    }

    /// "one hundred thirty five", "a hundred and eighty five", "two hundred".
    private static func hundreds(_ words: ArraySlice<String>) -> Reading<Int>? {
        guard let multiplier = words.first.flatMap({ multipliers[$0] }), words.dropFirst().first == "hundred" else { return nil }
        let rest = words.dropFirst(2)
        guard let tail = twoDigits(rest.first == "and" ? rest.dropFirst() : rest) else {
            return Reading(value: multiplier * 100, rest: rest)
        }
        return Reading(value: multiplier * 100 + tail.value, rest: tail.rest)
    }

    /// "one thirty five", "three fifteen", "four oh five": the hundreds digit, then the rest.
    private static func colloquialHundreds(_ words: ArraySlice<String>) -> Reading<Int>? {
        guard let hundreds = words.first.flatMap({ units[$0] }) else { return nil }
        let rest = words.dropFirst()
        return (ohUnit(rest) ?? tensAndTeens(rest)).map { Reading(value: hundreds * 100 + $0.value, rest: $0.rest) }
    }

    private static func ohUnit(_ words: ArraySlice<String>) -> Reading<Int>? {
        guard words.first == "oh", let unit = words.dropFirst().first.flatMap({ units[$0] }) else { return nil }
        return Reading(value: unit, rest: words.dropFirst(2))
    }

    private static func tensAndTeens(_ words: ArraySlice<String>) -> Reading<Int>? {
        guard let first = words.first, tens[first] != nil || teens[first] != nil else { return nil }
        return twoDigits(words)
    }

    /// "thirty five", "fifteen", "eight".
    private static func twoDigits(_ words: ArraySlice<String>) -> Reading<Int>? {
        guard let first = words.first else { return nil }
        if let tens = tens[first] { return tensAndUnit(tens, words.dropFirst()) }
        return (teens[first] ?? units[first]).map { Reading(value: $0, rest: words.dropFirst()) }
    }

    /// A "four" a number follows is the "for" of "ninety four five", so "ninety" stops before it.
    private static func tensAndUnit(_ tens: Int, _ rest: ArraySlice<String>) -> Reading<Int> {
        guard let unit = rest.first.flatMap({ units[$0] }), rest.first != "four" || read(rest.dropFirst()) == nil else {
            return Reading(value: tens, rest: rest)
        }
        return Reading(value: tens + unit, rest: rest.dropFirst())
    }

    private static let halves: [[String]] = [["and", "a", "half"], ["1/2"]]

    /// ".5" for "and a half", a written "1/2", or "point five".
    private static func fraction(_ words: ArraySlice<String>) -> Reading<String>? {
        if let half = halves.first(where: { words.starts(with: $0) }) {
            return Reading(value: ".5", rest: words.dropFirst(half.count))
        }
        guard words.first == "point" else { return nil }
        let digits = words.dropFirst().prefix { digit($0) != nil }.compactMap(digit)
        guard !digits.isEmpty else { return nil }
        return Reading(value: "." + digits.joined(), rest: words.dropFirst(1 + digits.count))
    }

    private static func digit(_ word: String) -> String? {
        units[word].map(String.init) ?? (word.wholeMatch(of: /\d+/) != nil ? word : nil)
    }
}
