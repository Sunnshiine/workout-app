import Foundation

/// A speech transcript as the words the grammar reads.
enum SpokenTranscript {
    /// Lowercased words, digit runs, a written "1/2", and every other symbol on its own, with
    /// punctuation dropped and spelled-out abbreviations ("r p e", "b w", "body weight") joined into
    /// one word. A pound sign is the "pounds" after its number, "½" is "1/2", a clock time is the
    /// number its digits spell ("1:35"), and a "-" that starts a number is a minus sign, never dropped.
    static func words(in transcript: String) -> [String] {
        let tokens = transcript.lowercased()
            .replacing("×", with: " x ")
            .replacing("½", with: " 1/2 ")
            .replacing(/['‘’]/, with: "")
            .replacing(/£\s*([0-9]+(?:\.[0-9]+)?)/) { "\($0.1) pounds" }
            .replacing(/([0-9]{1,2}):([0-9]{2})/) { "\($0.1)\($0.2)" }
            .replacing(/(^|\s)-(?=[0-9])/) { "\($0.1)−" }
            .matches(of: /1\/2|[0-9]+(?:\.[0-9]+)?|bw(?=x)|[a-z]+|[^\s.,!?;:"“”()\-–—…]/)
            .map { String($0.output) }
        return joiningPhrases(tokens)
    }

    private static let phrases: [(words: [String], word: String)] = [
        (["r", "p", "e"], "rpe"), (["r", "p"], "rpe"), (["b", "w"], "bw"), (["body", "weight"], "bw"), (["k", "g"], "kg"),
        (["thank", "you"], "thanks")
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

/// One word of a transcript as the grammar knows it. Every word the grammar reads is a row of
/// `entries`, and any other word rejects the transcript.
enum SpokenWord: Equatable, Sendable {
    case digits(String)
    case unit(Int)
    /// The unit 4, which between a weight and a number is the "for" of "135 four 5", unless a tens
    /// word before it takes it, as "ninety four" does.
    case four
    case teen(Int)
    case tens(Int)
    case hundred
    /// The one of "a hundred" and the a of "and a half".
    case a
    /// The zero of "four oh five".
    case oh
    /// The and of "a hundred and five" and "eight and a half", and otherwise a misheard "at".
    case and
    case point
    case half
    /// A written "1/2".
    case halfSign
    case token(SpokenToken)
    /// A choice, as in "20 or 25 reps", though the recognizer writes it for the "for" of "135 or 5".
    case or
    /// The "for" of "95 pounds per six" after bodyweight or a weight heavier than the reps.
    case per
    /// "to" and "too", the 2 of "185 for to" and "to reps", and otherwise the "at" the recognizer
    /// mishears in "225 for 3 to 8".
    case to
    case kilograms
    case filler
    case unknown

    init(_ word: String) {
        self = Self.lexicon[word] ?? (word.wholeMatch(of: /(?:0|[1-9][0-9]*)(?:\.[0-9]+)?/) == nil ? .unknown : .digits(word))
    }

    /// The word read on its own, outside a number and where no homophone reading fits: a token,
    /// nothing for a filler, or the rejection a word outside the grammar earns.
    var alone: Result<SpokenToken?, SpokenSet.Rejection> {
        switch self {
        case .token(let token): .success(token)
        case .and: .success(.misheardAt(isFiller: true))
        case .to: .success(.misheardAt(isFiller: false))
        case .a, .oh, .filler: .success(nil)
        case .kilograms: .failure(.kilograms)
        default: .failure(.unrecognized)
        }
    }

    /// A word that adds nothing to a transcript read on its own, as "um", "the", and "and" do.
    var isFiller: Bool {
        switch alone {
        case .success(let token): token?.isFiller ?? true
        case .failure: false
        }
    }

    var unit: Int? {
        switch self {
        case .unit(let unit): unit
        case .four: 4
        default: nil
        }
    }

    /// The number of hundreds this word gives the "hundred" after it.
    var multiplier: Int? { self == .a ? 1 : unit }

    /// The digits this word spells after "point": "five" is 5, "25" is 25.
    var decimalDigits: String? {
        guard case .digits(let digits) = self else { return unit.map(String.init) }
        return digits.contains(".") ? nil : digits
    }

    private static let lexicon: [String: SpokenWord] = Dictionary(
        uniqueKeysWithValues: entries.flatMap { entry in entry.words.map { ($0, entry.word) } }
    )

    private static let entries: [(words: [String], word: SpokenWord)] = [
        (["zero"], .unit(0)), (["one"], .unit(1)), (["two"], .unit(2)), (["three"], .unit(3)), (["four"], .four),
        (["five"], .unit(5)), (["six"], .unit(6)), (["seven"], .unit(7)), (["eight", "ate"], .unit(8)), (["nine"], .unit(9)),
        (["ten"], .teen(10)), (["eleven"], .teen(11)), (["twelve"], .teen(12)), (["thirteen"], .teen(13)),
        (["fourteen"], .teen(14)), (["fifteen"], .teen(15)), (["sixteen"], .teen(16)), (["seventeen"], .teen(17)),
        (["eighteen"], .teen(18)), (["nineteen"], .teen(19)),
        (["twenty"], .tens(20)), (["thirty"], .tens(30)), (["forty"], .tens(40)), (["fifty"], .tens(50)),
        (["sixty"], .tens(60)), (["seventy"], .tens(70)), (["eighty"], .tens(80)), (["ninety"], .tens(90)),
        (["hundred"], .hundred), (["a"], .a), (["oh"], .oh), (["and"], .and), (["point"], .point), (["half"], .half),
        (["1/2"], .halfSign),
        (["for", "x", "by", "times"], .token(.marker(.separator))),
        (["pound", "pounds", "lb", "lbs"], .token(.marker(.pounds))),
        (["rep", "reps"], .token(.marker(.reps))),
        (["rpe", "rp", "@", "rte", "rtd", "rtv"], .token(.marker(.rpe))),
        (["at"], .token(.marker(.at))),
        (["with"], .token(.marker(.with))),
        (["bw", "bodyweight"], .token(.bodyweight)),
        (["of"], .token(.misheardAt(isFiller: true))),
        (["add"], .token(.misheardAt(isFiller: false))),
        (["or"], .or), (["per"], .per),
        (["to", "too"], .to),
        (["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"], .kilograms),
        (
            [
                "um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm", "mm", "okay", "ok", "so", "yeah", "yes", "please", "thanks", "the",
                "an", "i", "just", "hit", "did", "got", "then"
            ],
            .filler
        )
    ]
}

/// Same again and skip, each recognized by a trigger word and allowed only its own vocabulary.
/// Read before any number, because "skip this one" holds the number word "one".
struct SpokenCommand {
    let triggers: Set<String>
    let vocabulary: Set<String>
    let spokenSet: SpokenSet

    /// What the athlete says, which happens to spell the Set Log wire token. A spoken skip reaches
    /// the Sheet through `WorkoutStore.skip`, so the word and the token change independently.
    static let spokenSkipWord = "skip"

    static let all = [
        SpokenCommand(
            triggers: [spokenSkipWord, "skipped"],
            vocabulary: [spokenSkipWord, "skipped", "it", "this", "that", "set", "one"],
            spokenSet: .skip
        ),
        SpokenCommand(
            triggers: ["same", "again", "repeat"],
            vocabulary: ["same", "again", "repeat", "as", "last", "before", "do", "set", "one", "that", "it", "previous"],
            spokenSet: .sameAgain
        )
    ]

    /// The words that name a Session, as in "same as last time".
    static let sessionWords: Set<String> = ["time", "week"]

    /// The command, unless its words name which Set or Session, as "skip set one" and "same as last
    /// time" do, because a command acts only on this Set and the one before it. The "one" of "this
    /// one" and "that one" is this Set.
    func read(_ words: [String]) throws(SpokenSet.Rejection) -> SpokenSet {
        guard !zip([""] + words, words).contains(where: Self.namesASetOrSession) else { throw .ambiguous }
        guard vocabulary.isSuperset(of: words) else { throw .unrecognized }
        return spokenSet
    }

    private static func namesASetOrSession(after previous: String, _ word: String) -> Bool {
        guard !sessionWords.contains(word) else { return true }
        return SpokenNumber.read([SpokenWord(word)][...]) != nil && !(word == "one" && ["this", "that"].contains(previous))
    }
}

/// One number as an athlete says it: "185", "one thirty five", "a hundred and eighty five",
/// "four oh five", "eight and a half", "one eighty seven point five". `digits` is the number as the
/// transcriber wrote it, before any half or "point" said after it, and nil when it was said in words.
struct SpokenNumber: Equatable, Sendable {
    let value: Double
    let digits: String?
    /// Said last with the start of a half or a decimal after it, as the 8 of "at 8 and a" or "at 8
    /// point": the recognizer cut off the rest of the number.
    var isCutOff = false

    /// Four or more digits before any point, which no Set holds: numbers the recognizer ran together.
    var isFused: Bool { (digits?.prefix { $0 != "." }.count ?? 0) >= 4 }
}

extension SpokenNumber {
    typealias Words = ArraySlice<SpokenWord>

    struct Reading<Number> {
        let number: Number
        let rest: Words
    }

    /// The number the words start with, read as far as it goes, with the words after it.
    static func read(_ words: Words) -> Reading<SpokenNumber>? {
        guard let whole = written(words) ?? said(words) else { return nil }
        guard whole.number.value.rounded() == whole.number.value else { return whole }
        return fraction(after: whole) ?? cutOffFraction(after: whole) ?? whole
    }

    private static func written(_ words: Words) -> Reading<SpokenNumber>? {
        guard case .digits(let digits)? = words.first, let value = Double(digits) else { return nil }
        return Reading(number: SpokenNumber(value: value, digits: digits), rest: words.dropFirst())
    }

    private static func said(_ words: Words) -> Reading<SpokenNumber>? {
        (hundreds(words) ?? colloquialHundreds(words) ?? twoDigits(words)).map {
            Reading(number: SpokenNumber(value: Double($0.number), digits: nil), rest: $0.rest)
        }
    }

    /// "one hundred thirty five", "a hundred and eighty five", "hundred eighty five", "two hundred".
    private static func hundreds(_ words: Words) -> Reading<Int>? {
        guard let hundreds = hundredsWord(words) else { return nil }
        let rest = hundreds.rest.first == .and ? hundreds.rest.dropFirst() : hundreds.rest
        guard let tail = twoDigits(rest) else { return hundreds }
        return Reading(number: hundreds.number + tail.number, rest: tail.rest)
    }

    private static func hundredsWord(_ words: Words) -> Reading<Int>? {
        if words.first == .hundred { return Reading(number: 100, rest: words.dropFirst()) }
        guard let multiplier = words.first?.multiplier, words.dropFirst().first == .hundred else { return nil }
        return Reading(number: multiplier * 100, rest: words.dropFirst(2))
    }

    /// "one thirty five", "three fifteen", "four oh five": the hundreds digit, then the rest.
    private static func colloquialHundreds(_ words: Words) -> Reading<Int>? {
        guard let hundreds = words.first?.unit else { return nil }
        let rest = words.dropFirst()
        return (ohUnit(rest) ?? tensOrTeen(rest)).map { Reading(number: hundreds * 100 + $0.number, rest: $0.rest) }
    }

    private static func ohUnit(_ words: Words) -> Reading<Int>? {
        guard words.first == .oh, let unit = words.dropFirst().first?.unit else { return nil }
        return Reading(number: unit, rest: words.dropFirst(2))
    }

    /// Not a unit, because "nine five" makes no one number.
    private static func tensOrTeen(_ words: Words) -> Reading<Int>? {
        guard words.first?.unit == nil else { return nil }
        return twoDigits(words)
    }

    /// "thirty five", "fifteen", "eight".
    private static func twoDigits(_ words: Words) -> Reading<Int>? {
        switch words.first {
        case .tens(let tens)?: tensAndUnit(tens, words.dropFirst())
        case .teen(let teen)?: Reading(number: teen, rest: words.dropFirst())
        default: words.first?.unit.map { Reading(number: $0, rest: words.dropFirst()) }
        }
    }

    private static func tensAndUnit(_ tens: Int, _ rest: Words) -> Reading<Int> {
        guard let unit = rest.first?.unit else { return Reading(number: tens, rest: rest) }
        return Reading(number: tens + unit, rest: rest.dropFirst())
    }

    /// A half or the digits after "point".
    private static func fraction(after whole: Reading<SpokenNumber>) -> Reading<SpokenNumber>? {
        (half(whole.rest) ?? decimal(whole.rest)).map {
            Reading(number: SpokenNumber(value: whole.number.value + $0.number, digits: whole.number.digits), rest: $0.rest)
        }
    }

    private static let fractionStarts: [[SpokenWord]] = [[.and], [.and, .a], [.point]]

    /// The number cut off when all that follows it, filler aside, is the start of a half or a decimal.
    private static func cutOffFraction(after whole: Reading<SpokenNumber>) -> Reading<SpokenNumber>? {
        guard fractionStarts.contains(whole.rest.filter { $0 != .filler }) else { return nil }
        return Reading(number: SpokenNumber(value: whole.number.value, digits: whole.number.digits, isCutOff: true), rest: [])
    }

    private static let halves: [[SpokenWord]] = [[.and, .a, .half], [.and, .half], [.halfSign]]

    private static func half(_ words: Words) -> Reading<Double>? {
        halves.first { words.starts(with: $0) }.map { Reading(number: 0.5, rest: words.dropFirst($0.count)) }
    }

    private static func decimal(_ words: Words) -> Reading<Double>? {
        guard words.first == .point else { return nil }
        let digits = words.dropFirst().prefix { $0.decimalDigits != nil }.compactMap(\.decimalDigits)
        guard !digits.isEmpty, let fraction = Double("0." + digits.joined()) else { return nil }
        return Reading(number: fraction, rest: words.dropFirst(1 + digits.count))
    }
}

/// The transcript's words read into numbers, bodyweight, and the markers that label them.
struct SpokenTokens {
    private(set) var tokens: [SpokenToken] = []

    init(_ words: [SpokenWord]) throws(SpokenSet.Rejection) {
        var rest = words[...]
        while let word = rest.first {
            rest = try read(word, rest)
        }
    }

    private mutating func read(_ word: SpokenWord, _ words: SpokenNumber.Words) throws(SpokenSet.Rejection) -> SpokenNumber.Words {
        if let homophone = try homophone(word, before: words.dropFirst()) {
            tokens.append(homophone)
        } else if let number = SpokenNumber.read(words) {
            try append(number.number)
            return number.rest
        } else if let token = try word.alone.get() {
            tokens.append(token)
        }
        return words.dropFirst()
    }

    /// "four" between a weight and a number is the "for" of "135 four 5", and "per" is too before
    /// fewer reps. "or" sounds like "for" but offers a choice, so it is ambiguous. "to" and "too" are
    /// 2 only where a number is asked for: "315 for to", "to reps", and a misheard "at" elsewhere.
    private func homophone(_ word: SpokenWord, before next: SpokenNumber.Words) throws(SpokenSet.Rejection) -> SpokenToken? {
        switch word {
        case .four: separator(before: next)
        case .per: try separatorBeforeFewerReps(next)
        case .or: throw .ambiguous
        case .to: two(before: next)
        default: nil
        }
    }

    private func separator(before next: SpokenNumber.Words) -> SpokenToken? {
        guard lastValue?.amount != nil, SpokenNumber.read(next) != nil else { return nil }
        return .marker(.separator)
    }

    /// A weight for reps falls from the weight to the reps, so "per" between bodyweight or a weight and
    /// fewer reps is its "for". Between any other two numbers it may be a rate or a range, as in
    /// "25 per 30", and ambiguous.
    private func separatorBeforeFewerReps(_ next: SpokenNumber.Words) throws(SpokenSet.Rejection) -> SpokenToken? {
        guard let reps = SpokenNumber.read(next)?.number.value, let weight = lastValue?.amount else { return nil }
        guard case .number(let pounds) = weight else { return .marker(.separator) }
        guard pounds > reps else { throw .ambiguous }
        return .marker(.separator)
    }

    private var lastValue: SpokenToken? {
        tokens.last { $0 != .marker(.pounds) }
    }

    private func two(before next: SpokenNumber.Words) -> SpokenToken? {
        guard (tokens.last?.asksForAValue ?? false) || next.first == .token(.marker(.reps)) else { return nil }
        return .number(SpokenNumber(value: 2, digits: nil))
    }

    /// Two numbers said in words in a row, as "nine five", make no one number.
    private mutating func append(_ number: SpokenNumber) throws(SpokenSet.Rejection) {
        guard !number.isFused else { throw .fusedNumber }
        guard case .number(let previous)? = tokens.last, previous.digits == nil, number.digits == nil else {
            tokens.append(.number(number))
            return
        }
        throw .ambiguous
    }
}
