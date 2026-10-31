import Foundation

/// A length of time as a coach writes one, in whole seconds from 1 second to 60 minutes: `15 sec`,
/// `15s`, `15-sec`, `15 seconds`, `40"`, `:15`, `0:45`, `1:30`, `1 min`, `1.5 min`, `2 minutes`,
/// `1 min 30 sec`, `1m30s`, in any casing. A range reads as its low end, as a rep range does, and
/// only when its ends both resolve, low end first: `30-45 sec`, `0:30 – 0:45`, with any dash
/// between them. A Cadence is never one, because a clock time has one colon and two-digit seconds:
/// `0:5:0` and `2-3:1:0` read as nothing.
struct EffortDuration: Equatable, Hashable, Sendable {
    /// One duration written in prose, and where.
    struct Written: Equatable {
        let duration: EffortDuration
        let range: Range<String.Index>
        /// Written with a double prime, as `20"` is, which a coach also writes for inches.
        let isDoublePrime: Bool
    }

    static let longestSeconds = 60 * 60

    let seconds: Int

    /// Nil unless the whole of `text`, trimmed and less one closing full stop, is one duration.
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let unstopped = trimmed.hasSuffix(".") ? trimmed.dropLast() : Substring(trimmed)
        guard let written = Self.written(in: String(unstopped)).first, written.range == unstopped.startIndex..<unstopped.endIndex else {
            return nil
        }
        self = written.duration
    }

    private init?(seconds: Double) {
        guard seconds.rounded() == seconds, (1...Double(Self.longestSeconds)).contains(seconds) else { return nil }
        self.seconds = Int(seconds)
    }

    /// Every duration `prose` writes, in order. A number that continues a run of numbers, as the
    /// `2-1 min` of `1-2-3-3-2-1 min` does, or that runs on into another colon, as `1:30:0` does,
    /// is not one, and neither is a double prime that closes a quotation.
    static func written(in prose: String) -> [Written] {
        let count =
            #/
            (?<low> [0-9]+ (?: \. [0-9]+ )? )
            (?: \s* [-–—‑‒−] \s* (?<high> [0-9]+ (?: \. [0-9]+ )? ) )?
            (?:
                (?<doublePrime> ["″] )
                | \s* [-–—‑‒−]? \s* (?: seconds? | secs? | s )
                | \s* [-–—‑‒−]? \s* (?<minutes> minutes? | mins? | m )
                  (?: \s* (?<addedSeconds> [0-5]? [0-9] ) \s* (?: seconds? | secs? | s ) )?
            )
            (?! \w )
            /#
        let clock =
            #/
            (?<lowMinutes> [0-9]{1,2} )? : (?<lowSeconds> [0-9]{2} )
            (?: \s* [-–—‑‒−] \s* (?<highMinutes> [0-9]{1,2} )? : (?<highSeconds> [0-9]{2} ) )?
            (?: \s* (?: seconds? | secs? | s | minutes? | mins? ) \b )?
            /#
        let counted = prose.matches(of: count.ignoresCase()).map { match in
            let unit = CountUnit(minutes: match.minutes, addedSeconds: match.addedSeconds)
            let ends = [match.low, match.high].compactMap { $0 }.map { Double($0).flatMap(unit.seconds) }
            return WrittenEnds(range: match.range, seconds: ends, isDoublePrime: match.doublePrime != nil)
        }
        let clocked = prose.matches(of: clock.ignoresCase()).map { match in
            let high = match.highSeconds.map { [clockSeconds(match.highMinutes, $0)] } ?? []
            return WrittenEnds(range: match.range, seconds: [clockSeconds(match.lowMinutes, match.lowSeconds)] + high, isDoublePrime: false)
        }
        return (counted + clocked)
            .filter { standsAlone($0, in: prose) }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .compactMap { ends in ends.duration.map { Written(duration: $0, range: ends.range, isDoublePrime: ends.isDoublePrime) } }
    }

    /// What a count is counted in. A bare `m` is minutes only with seconds after it, as in `1m30s`,
    /// because alone it is as likely metres.
    private enum CountUnit {
        case seconds
        case minutes(plusSeconds: Int)
        case unreadable

        init(minutes: Substring?, addedSeconds: Substring?) {
            guard let minutes else {
                self = .seconds
                return
            }
            let added = addedSeconds.flatMap { Int($0) }
            self = minutes.count == 1 && added == nil ? .unreadable : .minutes(plusSeconds: added ?? 0)
        }

        func seconds(_ count: Double) -> Double? {
            switch self {
            case .seconds: count
            case .minutes(let plusSeconds): count * 60 + Double(plusSeconds)
            case .unreadable: nil
            }
        }
    }

    /// The ends of one written duration, in seconds, low end first. Nil for an end that is no number.
    private struct WrittenEnds {
        let range: Range<String.Index>
        let seconds: [Double?]
        let isDoublePrime: Bool

        /// The low end, when every end is a duration and none runs backward.
        var duration: EffortDuration? {
            let durations = seconds.compactMap { $0.flatMap(EffortDuration.init(seconds:)) }
            guard durations.count == seconds.count, let low = durations.first, let high = durations.last, low.seconds <= high.seconds else {
                return nil
            }
            return low
        }
    }

    private static func clockSeconds(_ minutes: Substring?, _ seconds: Substring) -> Double? {
        guard let seconds = Int(seconds), seconds < 60 else { return nil }
        return Double((minutes.flatMap { Int($0) } ?? 0) * 60 + seconds)
    }

    /// False for a match that a digit or a colon runs into on either side, or a decimal point
    /// before it, or that a dash joins to the number before it. Such a match is a piece of a
    /// Cadence, a longer number, or a pyramid such as "3-4-5 min". False too for a `"` that
    /// closes a quotation, which an odd count of `"` before it opens.
    private static func standsAlone(_ ends: WrittenEnds, in prose: String) -> Bool {
        let before = prose[..<ends.range.lowerBound]
        let closesAQuotation = prose[ends.range].hasSuffix("\"") && before.count { $0 == "\"" } % 2 == 1
        return !runsIn(prose[ends.range.upperBound...].first, marks: ":") && !runsIn(before.last, marks: ":.")
            && !endsInANumberAndDash(before) && !closesAQuotation
    }

    private static func runsIn(_ character: Character?, marks: String) -> Bool {
        guard let character else { return false }
        return character.isASCIIDigit || marks.contains(character)
    }

    /// Every dash a coach's keyboard writes between two numbers: hyphen, en dash, em dash,
    /// non-breaking hyphen, figure dash, and minus sign. The duration patterns above spell the
    /// same set.
    private static let dashes = "-–—‑‒−"

    private static func endsInANumberAndDash(_ text: Substring) -> Bool {
        let beforeDash = text.reversed().drop { $0 == " " }
        guard let dash = beforeDash.first, dashes.contains(dash) else { return false }
        return beforeDash.dropFirst().drop { $0 == " " }.first?.isASCIIDigit ?? false
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
