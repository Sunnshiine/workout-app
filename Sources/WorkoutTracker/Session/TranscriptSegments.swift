import Foundation

/// The phrases a speech transcriber reports for one press, each with its own alternatives.
struct TranscriptSegments: Sendable {
    struct Segment: Equatable, Sendable {
        let top: String
        /// May repeat `top`.
        let alternatives: [String]
    }

    private struct Heard: Sendable {
        let segment: Segment
        let start: Double
        let end: Double
        let isFinal: Bool

        /// Revisions of one phrase start together, even reported with no length of audio.
        func overlaps(_ other: Heard) -> Bool {
            start == other.start || (start < other.end && other.start < end)
        }
    }

    /// In the order spoken.
    private var phrases: [Heard] = []

    /// A transcriber revises a phrase it is still hearing until it finishes it, so a phrase
    /// replaces each tentative one over the same audio and never a finished one.
    /// DictationTranscriber never finishes one, so its tentative phrases are all that was heard.
    /// Times are seconds into the press.
    mutating func receive(_ segment: Segment, from start: Double, to end: Double, isFinal: Bool) {
        let heard = Heard(segment: segment, start: start, end: end, isFinal: isFinal)
        phrases.removeAll { !$0.isFinal && $0.overlaps(heard) }
        phrases.insert(heard, at: phrases.firstIndex { $0.start > start } ?? phrases.endIndex)
    }

    var heard: String {
        Self.transcript(segments.map(\.top))
    }

    /// The top transcript, then each phrase swapped for one of its alternatives in turn, for
    /// `SpokenSet.parse(candidates:)`.
    var candidates: [String] {
        let segments = segments
        let tops = segments.map(\.top)
        let swaps = segments.indices.flatMap { index in
            segments[index].alternatives.map { alternative in
                var swapped = tops
                swapped[index] = alternative
                return Self.transcript(swapped)
            }
        }
        var seen = Set<String>()
        return ([Self.transcript(tops)] + swaps).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var segments: [Segment] {
        phrases.map(\.segment)
    }

    /// SpeechTranscriber starts each phrase after the first with a space; a phrase without one
    /// gets one.
    private static func transcript(_ phrases: [String]) -> String {
        phrases.reduce(into: "") { transcript, phrase in
            let touches = !(transcript.last?.isWhitespace ?? true) && !(phrase.first?.isWhitespace ?? true)
            transcript += touches ? " " + phrase : phrase
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
