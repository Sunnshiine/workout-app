import Foundation

/// The phrases a speech transcriber reports for one press, each with its own alternatives.
struct TranscriptSegments: Sendable {
    struct Segment: Equatable, Sendable {
        let top: String
        /// May repeat `top`.
        let alternatives: [String]
    }

    private var finished: [Segment] = []
    /// A transcriber revises the phrase it is still hearing until it finishes it, and
    /// DictationTranscriber never finishes one, so its last result is all that was heard.
    private var tentative: Segment?

    mutating func receive(_ segment: Segment, isFinal: Bool) {
        if isFinal {
            finished.append(segment)
            tentative = nil
        } else {
            tentative = segment
        }
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
        finished + (tentative.map { [$0] } ?? [])
    }

    /// Each phrase carries its own leading space.
    private static func transcript(_ phrases: [String]) -> String {
        phrases.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
