import Foundation

/// One number as an athlete says it: "185", "one thirty five", "a hundred and eighty five",
/// "four oh five", "eight and a half", "one eighty seven point five", "one thousand and five",
/// "eleven hundred", "ten fifty". `digits` is the number as the
/// transcriber wrote it, before any half or "point" said after it, and nil when it was said in words.
struct SpokenNumber: Equatable, Sendable {
    let value: Double
    let digits: String?
    /// Said last with the start of a half or a decimal after it, as the 8 of "at 8 and a" or "at 8
    /// point": the recognizer cut off the rest of the number.
    var isCutOff = false

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
        (thousands(words) ?? hundreds(words) ?? colloquialHundreds(words) ?? twoDigits(words)).map {
            Reading(number: SpokenNumber(value: Double($0.number), digits: nil), rest: $0.rest)
        }
    }

    /// "one thousand", "a thousand and five", "two thousand two hundred", "thousand fifty".
    private static func thousands(_ words: Words) -> Reading<Int>? {
        scaled(words, by: .thousand, 1000).map { adding({ hundreds($0) ?? twoDigits($0) }, to: $0) }
    }

    /// "one hundred thirty five", "a hundred and eighty five", "hundred eighty five", "eleven hundred".
    private static func hundreds(_ words: Words) -> Reading<Int>? {
        scaled(words, by: .hundred, 100).map { adding(twoDigits, to: $0) }
    }

    /// "hundred" or "thousand" alone, or after how many: "a hundred", "two thousand", "fifteen hundred".
    private static func scaled(_ words: Words, by word: SpokenWord, _ scale: Int) -> Reading<Int>? {
        if words.first == word { return Reading(number: scale, rest: words.dropFirst()) }
        guard let count = words.first == .a ? Reading(number: 1, rest: words.dropFirst()) : twoDigits(words),
            count.rest.first == word
        else { return nil }
        return Reading(number: count.number * scale, rest: count.rest.dropFirst())
    }

    /// The number after `head`, with or without "and" before it, added to it, as the 5 of "a hundred
    /// and five" and "one thousand five". With no number after it, an "and" is left for a half.
    private static func adding(_ tail: (Words) -> Reading<Int>?, to head: Reading<Int>) -> Reading<Int> {
        let rest = head.rest.first == .and ? head.rest.dropFirst() : head.rest
        guard let tail = tail(rest) else { return head }
        return Reading(number: head.number + tail.number, rest: tail.rest)
    }

    /// "one thirty five", "three fifteen", "four oh five", "ten fifty": the hundreds, then the rest.
    private static func colloquialHundreds(_ words: Words) -> Reading<Int>? {
        guard let hundreds = words.first?.unit ?? words.first?.teen else { return nil }
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
