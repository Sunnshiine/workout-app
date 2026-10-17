import Foundation

/// A number, bodyweight, or a word that labels one, as the grammar's phrases read them.
enum SpokenToken: Equatable, Sendable {
    case number(SpokenNumber)
    case bodyweight
    case marker(SpokenMarker)
    /// "and", "of", or "add" where "at" may have been said, so the number after it is no RPE heard.
    /// "and" and "of" are filler anywhere else.
    case misheardAt(isFiller: Bool)

    var amount: SpokenAmount? {
        switch self {
        case .number(let number): .number(number.value)
        case .bodyweight: .bodyweight
        default: nil
        }
    }

    /// A word that asks for the number after it: the reps after "for", the RPE after "at".
    var asksForAValue: Bool {
        switch self {
        case .marker(.separator), .marker(.at), .marker(.rpe), .misheardAt: true
        default: false
        }
    }

    /// Two digits, the second 6 to 9, that may be a rep count and an RPE run together, as "49" for "4 at 9".
    var mayBeRepsAtAnRPE: Bool {
        guard case .number(let number) = self else { return false }
        return number.digits?.wholeMatch(of: /[1-9][6-9]/) != nil
    }

    /// A word that adds nothing where no phrase takes it: the "and" and "of" that may be a misheard
    /// "at", and the "with" before a weight.
    var isFiller: Bool {
        switch self {
        case .misheardAt(let isFiller): isFiller
        case .marker(.with): true
        default: false
        }
    }

    /// The step that takes this token as a word rather than a value.
    var wordStep: SpokenStep? {
        switch self {
        case .marker(let marker): .marker(marker)
        case .misheardAt: .misheardAt
        default: nil
        }
    }
}

enum SpokenMarker: Equatable, Sendable {
    /// "for", "x", "by", "times", or a homophone of "for" between a weight and a number: weight
    /// before it, reps after it.
    case separator
    case pounds
    case reps
    /// "RPE", "@", or the "RTE", "RTD", or "RTV" a recognizer hears for "RPE".
    case rpe
    case at
    case with
}

enum SpokenAmount: Equatable, Sendable {
    case number(Double)
    case bodyweight
}

/// A value a phrase gives one field, or the field whose number the recognizer cut off.
enum SpokenClaim: Equatable, Sendable {
    case value(SetLogDraft.Field, SpokenAmount)
    case cutOff(SetLogDraft.Field)
}

/// What a phrase reads the number or bodyweight at one of its steps as.
enum SpokenReading: Equatable, Sendable {
    case weight
    /// Bodyweight said alone, never a number.
    case bodyweight
    case reps
    case rpe
    /// Any number after a misheard "at", which leaves the RPE cut off: "185 for 5 and 5" may be five
    /// Sets of five.
    case unheardRPE
    /// A number under 15 after "at", as in "at 9".
    case rpeAfterAt
    /// Bodyweight or a number of 15 or more after "at" or "with", as in "8 reps at 135".
    case weightAfterAt

    /// Under it, the number after "at" is an RPE and the number after "with" is no weight.
    static let lightestWeightAfterAt = 15.0

    var field: SetLogDraft.Field {
        switch self {
        case .weight, .bodyweight, .weightAfterAt: .weight
        case .reps: .reps
        case .rpe, .unheardRPE, .rpeAfterAt: .rpe
        }
    }

    func claim(_ token: SpokenToken) -> SpokenClaim? {
        guard let amount = token.amount, takes(amount) else { return nil }
        return self == .unheardRPE ? .cutOff(field) : .value(field, amount)
    }

    private func takes(_ amount: SpokenAmount) -> Bool {
        guard case .number(let number) = amount else { return field == .weight }
        return takes(number: number)
    }

    private func takes(number: Double) -> Bool {
        switch self {
        case .bodyweight: false
        case .rpeAfterAt: number < Self.lightestWeightAfterAt
        case .weightAfterAt: number >= Self.lightestWeightAfterAt
        default: true
        }
    }
}

/// One step of a phrase: a value it reads, a word it needs, or a step it may leave out.
enum SpokenStep: Equatable, Sendable {
    case value(SpokenReading)
    case marker(SpokenMarker)
    case misheardAt
    indirect case optional(SpokenStep)

    /// The claims this step makes of the token, or nil when the step does not take it.
    func take(_ token: SpokenToken) -> [SpokenClaim]? {
        switch self {
        case .value(let reading): reading.claim(token).map { [$0] }
        case .optional(let step): step.take(token)
        default: token.wordStep == self ? [] : nil
        }
    }

    var isOptional: Bool {
        guard case .optional = self else { return false }
        return true
    }

    var cutOffField: SetLogDraft.Field? {
        guard case .value(let reading) = self else { return nil }
        return reading.field
    }
}

/// A phrase matched so far: the claims its steps made and the tokens after them.
struct SpokenMatch {
    private(set) var claims: [SpokenClaim] = []
    private(set) var rest: ArraySlice<SpokenToken>
    private var last: SpokenToken?

    init(_ tokens: ArraySlice<SpokenToken>) {
        rest = tokens
    }

    /// Takes the next token if the step does, and passes an optional step that does not.
    mutating func take(_ step: SpokenStep) -> Bool {
        guard let token = rest.first, let taken = step.take(token) else { return step.isOptional }
        claims += taken
        last = token
        rest = rest.dropFirst()
        return true
    }

    /// The match with `step`'s field cut off, when the transcript ended right after a word that asks
    /// for a value, as "185 for" ends.
    func cutOff(at step: SpokenStep) -> SpokenMatch? {
        guard rest.isEmpty, last?.asksForAValue ?? false, let field = step.cutOffField else { return nil }
        var match = self
        match.claims.append(.cutOff(field))
        return match
    }
}

/// One way of saying values, as the steps a transcript's tokens must take in order. A number gets
/// a field only from a phrase, so a number no phrase takes rejects the transcript.
struct SpokenPhrase: Sendable {
    let steps: [SpokenStep]

    init(_ steps: SpokenStep...) {
        self.steps = steps
    }

    /// Tried in order, so the misheard "at" of "185 for 5 and 8" is read before "185 for 5" alone.
    static let all = [
        SpokenPhrase(
            .value(.weight),
            .optional(.marker(.pounds)),
            .marker(.separator),
            .value(.reps),
            .optional(.marker(.reps)),
            .misheardAt,
            .value(.unheardRPE)
        ),
        SpokenPhrase(.value(.weight), .optional(.marker(.pounds)), .marker(.separator), .value(.reps), .optional(.marker(.reps))),
        SpokenPhrase(.marker(.separator), .value(.reps), .optional(.marker(.reps))),
        SpokenPhrase(.value(.weight), .marker(.pounds)),
        SpokenPhrase(.value(.bodyweight)),
        SpokenPhrase(.value(.reps), .marker(.reps)),
        SpokenPhrase(.marker(.reps), .value(.reps)),
        SpokenPhrase(.optional(.marker(.at)), .marker(.rpe), .optional(.misheardAt), .value(.rpe)),
        SpokenPhrase(.value(.rpe), .marker(.rpe)),
        SpokenPhrase(.marker(.at), .value(.weight), .marker(.pounds)),
        SpokenPhrase(.marker(.at), .value(.rpeAfterAt)),
        SpokenPhrase(.marker(.at), .value(.weightAfterAt)),
        SpokenPhrase(.marker(.with), .value(.weightAfterAt))
    ]

    /// The match of every step from the tokens' start, or nil when a step is not there. A step cut off
    /// is the phrase's only when nothing it needs comes after it, so "at" said last is the RPE's.
    func match(_ tokens: ArraySlice<SpokenToken>) -> SpokenMatch? {
        var match = SpokenMatch(tokens)
        for (index, step) in steps.enumerated() {
            guard match.take(step) else {
                return steps[(index + 1)...].allSatisfy(\.isOptional) ? match.cutOff(at: step) : nil
            }
        }
        return match
    }

    /// The values the phrases read from the tokens. A rep count written as two digits right after
    /// "for", with no "reps" after it and no RPE said, is ambiguous when its second digit is 6 to 9,
    /// because "4 at 9" can reach the transcript as "49".
    static func values(in tokens: [SpokenToken]) throws(SpokenSet.Rejection) -> SpokenSet {
        let values = try SpokenSlots(claims(in: tokens)).spokenSet()
        guard case .values(_, _, .notSaid) = values, tokens.indices.contains(where: { readsTwoWays(tokens, at: $0) }) else {
            return values
        }
        throw .ambiguous
    }

    private static func claims(in tokens: [SpokenToken]) throws(SpokenSet.Rejection) -> [SpokenClaim] {
        var claims: [SpokenClaim] = []
        var rest = tokens[...]
        while let token = rest.first {
            if let match = firstMatch(rest) {
                claims += match.claims
                rest = match.rest
            } else {
                claims += try leftover(token, isLast: rest.count == 1)
                rest = rest.dropFirst()
            }
        }
        return claims
    }

    private static func firstMatch(_ tokens: ArraySlice<SpokenToken>) -> SpokenMatch? {
        all.lazy.compactMap { $0.match(tokens) }.first
    }

    /// A token no phrase takes. A misheard "at" said last is an RPE cut off and filler anywhere else
    /// is dropped, but a number no phrase takes is one no word places.
    private static func leftover(_ token: SpokenToken, isLast: Bool) throws(SpokenSet.Rejection) -> [SpokenClaim] {
        switch token {
        case .misheardAt where isLast: return [.cutOff(.rpe)]
        case .number: throw .ambiguous
        default:
            guard token.isFiller else { throw .unrecognized }
            return []
        }
    }

    private static func readsTwoWays(_ tokens: [SpokenToken], at index: Int) -> Bool {
        tokens[index].mayBeRepsAtAnRPE && tokens[..<index].last == .marker(.separator)
            && tokens[(index + 1)...].first != .marker(.reps)
    }
}

/// Weight, reps, and RPE as the phrases claim them. A value heard wins over the same field cut off,
/// so "at 9 RPE" has an RPE.
struct SpokenSlots {
    /// Under it, as the 4 of "4 for 5", a weight is a rep count misheard.
    static let lightestWeight = 5.0

    private var amounts: [SetLogDraft.Field: SpokenAmount] = [:]
    private var cutOff: Set<SetLogDraft.Field> = []

    init(_ claims: [SpokenClaim]) throws(SpokenSet.Rejection) {
        for claim in claims { try self.claim(claim) }
        guard !amounts.isEmpty else { throw .unrecognized }
    }

    /// The same number said twice for one value, as in "135 for eight, 8 reps", is not a conflict, but
    /// a second weight, even the same one, is a second Set, as in "185 for 5, 185 for 5".
    private mutating func claim(_ claim: SpokenClaim) throws(SpokenSet.Rejection) {
        switch claim {
        case .value(let field, let amount):
            let said = amounts.updateValue(amount, forKey: field)
            guard said == nil || (said == amount && field != .weight) else { throw .conflicting(field) }
        case .cutOff(let field):
            cutOff.insert(field)
        }
    }

    func spokenSet() throws(SpokenSet.Rejection) -> SpokenSet {
        .values(
            weight: spoken(.weight, try Self.weight(amounts[.weight])),
            reps: spoken(.reps, try Self.reps(amounts[.reps])),
            rpe: spoken(.rpe, try Self.rpe(amounts[.rpe]))
        )
    }

    private func spoken<Value: Equatable & Sendable>(_ field: SetLogDraft.Field, _ value: Value?) -> SpokenValue<Value> {
        if let value { return .heard(value) }
        return cutOff.contains(field) ? .cutOff : .notSaid
    }

    private static func weight(_ amount: SpokenAmount?) throws(SpokenSet.Rejection) -> Weight? {
        guard case .number(let pounds) = amount else { return amount.map { _ in .bodyweight } }
        guard pounds >= lightestWeight else { throw .outOfRange(.weight) }
        return .pounds(pounds)
    }

    private static func reps(_ amount: SpokenAmount?) throws(SpokenSet.Rejection) -> Int? {
        guard case .number(let count) = amount else { return nil }
        guard let reps = Int(exactly: count), (1...100).contains(reps) else { throw .outOfRange(.reps) }
        return reps
    }

    private static func rpe(_ amount: SpokenAmount?) throws(SpokenSet.Rejection) -> RPE? {
        guard case .number(let point) = amount else { return nil }
        guard let rpe = RPE(rawValue: point) else { throw .offLadderRPE(point) }
        return rpe
    }
}
