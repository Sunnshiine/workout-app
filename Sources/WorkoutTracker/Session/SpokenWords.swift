import Foundation

/// A speech transcript as the words the grammar reads.
enum SpokenTranscript {
    /// Lowercased words, digit runs, a written "1/2", and every other symbol on its own, with
    /// punctuation dropped and spelled-out abbreviations ("r p e", "b w", "body weight") joined into
    /// one word. A pound sign is the "pounds" after its number, "½" is "1/2", a clock time is the
    /// number its digits spell ("1:35"), a comma before exactly three digits separates thousands
    /// ("1,005"), and a "-" that starts a number is a minus sign, never dropped.
    static func words(in transcript: String) -> [String] {
        let tokens = transcript.lowercased()
            .replacing(/([0-9]),(?=[0-9]{3}(?![0-9]))/) { "\($0.1)" }
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

    /// The joined words include what the recognizer writes for "RPE" ("our fee") and "body weight"
    /// ("Bobby waits") when a lifter says them fast.
    private static let phrases: [(words: [String], word: String)] = [
        (["r", "p", "e"], "rpe"), (["r", "p"], "rpe"), (["our", "pe"], "rpe"), (["are", "pe"], "rpe"), (["our", "fee"], "rpe"),
        (["are", "fee"], "rpe"), (["r", "fee"], "rpe"), (["b", "w"], "bw"), (["body", "weight"], "bw"),
        (["body", "weights"], "bw"), (["body", "wait"], "bw"), (["body", "waits"], "bw"), (["bobby", "wait"], "bw"),
        (["bobby", "waits"], "bw"), (["k", "g"], "kg"), (["thank", "you"], "thanks")
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
    case thousand
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
    /// "single", "double", and "triple": a rep count said with its label, as "a triple" is "3 reps",
    /// and never part of a number, so "one eighty single" is no 181.
    case repCount(Int)
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

    var teen: Int? {
        guard case .teen(let teen) = self else { return nil }
        return teen
    }

    /// The digits this word spells after "point": "five" is 5, "25" is 25.
    var decimalDigits: String? {
        guard case .digits(let digits) = self else { return unit.map(String.init) }
        return digits.contains(".") ? nil : digits
    }

    private static let lexicon: [String: SpokenWord] = Dictionary(
        uniqueKeysWithValues: entries.flatMap { entry in entry.words.map { ($0, entry.word) } }
    )

    private static let entries: [(words: [String], word: SpokenWord)] = [
        (["zero"], .unit(0)), (["one"], .unit(1)), (["two"], .unit(2)), (["three"], .unit(3)),
        (["four"], .four),
        (["five"], .unit(5)), (["six"], .unit(6)), (["seven"], .unit(7)), (["eight", "ate", "age"], .unit(8)), (["nine"], .unit(9)),
        (["ten"], .teen(10)), (["eleven"], .teen(11)), (["twelve"], .teen(12)), (["thirteen"], .teen(13)),
        (["fourteen"], .teen(14)), (["fifteen"], .teen(15)), (["sixteen"], .teen(16)), (["seventeen"], .teen(17)),
        (["eighteen"], .teen(18)), (["nineteen"], .teen(19)),
        (["twenty"], .tens(20)), (["thirty"], .tens(30)), (["forty"], .tens(40)), (["fifty"], .tens(50)),
        (["sixty"], .tens(60)), (["seventy"], .tens(70)), (["eighty"], .tens(80)), (["ninety"], .tens(90)),
        (["hundred"], .hundred), (["thousand"], .thousand), (["a"], .a), (["oh"], .oh), (["and"], .and), (["point"], .point),
        (["half"], .half), (["1/2"], .halfSign), (["single"], .repCount(1)), (["double"], .repCount(2)), (["triple"], .repCount(3)),
        (["for", "x", "by", "times"], .token(.marker(.separator))),
        (["pound", "pounds", "lb", "lbs"], .token(.marker(.pounds))),
        (["rep", "reps", "rebs", "ribs", "rips", "representative", "representatives"], .token(.marker(.reps))),
        (["rpe", "rp", "@", "rte", "rtd", "rtv", "rpa", "pe"], .token(.marker(.rpe))),
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

/// The transcript's words read into numbers, bodyweight, and the markers that label them.
struct SpokenTokens {
    private(set) var tokens: [SpokenToken] = []

    /// A word the grammar rejects after a number that may be fused, as the "is" of "1358 is known",
    /// leaves no words to show the number hides no value, so the number is the first thing wrong.
    init(_ words: [SpokenWord]) throws(SpokenSet.Rejection) {
        var rest = words[...]
        do throws(SpokenSet.Rejection) {
            while let word = rest.first {
                rest = try read(word, rest)
            }
        } catch {
            throw tokens.contains(where: \.mayBeFused) ? .fusedNumber : error
        }
    }

    private mutating func read(_ word: SpokenWord, _ words: SpokenNumber.Words) throws(SpokenSet.Rejection) -> SpokenNumber.Words {
        if let homophone = try homophone(word, before: words.dropFirst()) {
            tokens.append(homophone)
        } else if let number = SpokenNumber.read(words) {
            try append(number.number)
            return number.rest
        } else {
            try readOutsideANumber(word, before: words.dropFirst())
        }
        return words.dropFirst()
    }

    /// A word no number takes: a rep count with its label, an article, or the word read alone.
    private mutating func readOutsideANumber(_ word: SpokenWord, before next: SpokenNumber.Words) throws(SpokenSet.Rejection) {
        switch word {
        case .repCount(let count):
            try append(SpokenNumber(value: Double(count), digits: nil))
            tokens.append(.marker(.reps))
        case .a where isArticle(before: next): tokens.append(.article)
        default:
            if let token = try word.alone.get() { tokens.append(token) }
        }
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

    /// "a" right after a number, or between "for" and a number, as in "135, a representative" and "135
    /// for a 9": a lifter counts with a bare number, so the "a" the recognizer wrote stands for words it
    /// lost, as the "8 at" of "135 for 8 at 9", and the number on either side of it is not the reps.
    private func isArticle(before next: SpokenNumber.Words) -> Bool {
        switch tokens.last {
        case .number?: true
        case .marker(.separator)?: SpokenNumber.read(next) != nil
        default: false
        }
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
        guard case .number(let previous)? = tokens.last, previous.digits == nil, number.digits == nil else {
            tokens.append(.number(number))
            return
        }
        throw .ambiguous
    }
}
