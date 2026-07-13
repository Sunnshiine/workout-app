import Foundation

/// The Exercise History sheet's presentation model (ADR-0012 data, ADR-0013 matching, revised
/// `DESIGN.md` §Exercise History Sheet).
///
/// Pure projection of the last ~5 Movement entries into Block-grouped, newest-first rows. All the
/// sheet's content-state rules live here so the view stays a dumb renderer: gutter labels with
/// Cadence, structured Sets split into load + muted RPE, inline skip markers, Legacy / Unstructured
/// text rendered *as entered*, and spelling-variant entries annotated *as "…"*. Movement matching
/// and the local fetch happen upstream; this type only orders, caps, groups, and annotates.
struct ExerciseHistorySheetPresentation: Equatable, Sendable {
    /// One Set within a history row.
    enum SetSegment: Equatable, Sendable {
        /// A structured Set Log split into its load (`27.5×10`) and muted RPE (`8`) so the view can
        /// tone them independently.
        case log(load: String, rpe: String?)
        /// A Skipped Set — rendered as a muted italic `skip` marker inline.
        case skip
        /// Raw entered text (a Legacy Log or Unstructured Set Log) — never normalized (ADR-0005).
        case raw(String)
    }

    /// One entry: a `Wn Dn` gutter with the entry's Cadence beneath, then its Sets on one line.
    struct Row: Equatable, Sendable {
        let gutter: String
        let cadence: String?
        let segments: [SetSegment]
        /// The whole entry is raw entered text (Legacy Log / fully Unstructured) — the view shows a
        /// muted *as entered* tag.
        let asEntered: Bool
        /// The entry's own entered base name when it differs beyond case from the viewed Exercise's
        /// — the view annotates it *as "…"* (ADR-0013). `nil` when it matches.
        let asName: String?
    }

    /// Entries sharing a Block (sheet tab), newest Block first.
    struct Block: Equatable, Sendable {
        let header: String
        let rows: [Row]
    }

    static let entryLimit = 5

    let title: String
    let subtitle: String
    let blocks: [Block]
    /// Whether this Movement's history could still deepen — it holds fewer than the capped ~5
    /// entries. The fill-in-progress affordance is scoped to this: a Movement already at the cap
    /// hides it even while a fill runs for other Movements (PRD #357 §4 — the affordance shows only
    /// "while history for the viewed Movement may still deepen").
    let mayStillDeepen: Bool

    var isEmpty: Bool { blocks.isEmpty }

    init(anchorBaseName: String, entries: [LastPerformedOccurrence]) {
        title = anchorBaseName
        subtitle = "Exercise History · last \(Self.entryLimit)"
        mayStillDeepen = entries.count < Self.entryLimit

        let recent = entries
            .sorted { $0.performedOn > $1.performedOn }
            .prefix(Self.entryLimit)

        var order: [String] = []
        var grouped: [String: [Row]] = [:]
        for entry in recent {
            let (header, gutter) = Self.splitSource(entry.source)
            if grouped[header] == nil { order.append(header) }
            grouped[header, default: []].append(Self.row(for: entry, gutter: gutter, anchorBaseName: anchorBaseName))
        }

        blocks = order.map { Block(header: $0, rows: grouped[$0] ?? []) }
    }

    /// `Block 27 · W1 D1` → (`BLOCK 27`, `W1 D1`). The gutter is the final ` · ` component; the
    /// Block header is everything before it, uppercased.
    private static func splitSource(_ source: String) -> (header: String, gutter: String) {
        guard let range = source.range(of: " · ", options: .backwards) else {
            return (source.uppercased(), "")
        }
        let header = String(source[..<range.lowerBound]).uppercased()
        let gutter = String(source[range.upperBound...])
        return (header, gutter)
    }

    private static func row(for entry: LastPerformedOccurrence, gutter: String, anchorBaseName: String) -> Row {
        let cadence = splitCadence(entry.fullName).cadence
        let (segments, asEntered) = segments(for: entry.resultText)
        let differsBeyondCase = entry.baseName.lowercased() != anchorBaseName.lowercased()
        return Row(
            gutter: gutter,
            cadence: cadence,
            segments: segments,
            asEntered: asEntered,
            asName: differsBeyondCase ? entry.baseName : nil
        )
    }

    /// Splits a display string into Set segments.
    ///
    /// Structured / partially-skipped entries join their Set tokens with `, ` (the extractor's
    /// separator), so a value with any structured or `skip` token is split token-by-token. A value
    /// with none — a Legacy Log or a fully Unstructured entry — is left whole and marked *as
    /// entered*, so its raw text (which may itself contain commas) is never normalized.
    ///
    /// In a *mixed* entry, an Unstructured Set Log that itself contains `", "` is split by the join
    /// above; adjacent `.raw` segments are coalesced back with `", "` so that raw text renders
    /// verbatim (ADR-0005 "never normalized") rather than as `·`-separated fragments. Structured and
    /// `skip` tokens break the raw run, so they still split correctly. (Two genuinely-separate
    /// Unstructured Set Logs merge into one `.raw` here — they are indistinguishable once ADR-0012
    /// persists a joined display *string*, and render identically either way.)
    private static func segments(for resultText: String) -> (segments: [SetSegment], asEntered: Bool) {
        let tokens = resultText.components(separatedBy: ", ")
        let classifications = tokens.map { SetLogToken.classify($0) }
        let isSetBased = classifications.contains { $0.setLog != nil || $0.state == .skipped }

        guard isSetBased else {
            return ([.raw(resultText)], true)
        }

        var segments: [SetSegment] = []
        for (token, classification) in zip(tokens, classifications) {
            if let log = classification.setLog {
                segments.append(.log(load: "\(log.weight.label)×\(log.reps)", rpe: rpeLabel(log.rpe)))
            } else if classification.state == .skipped {
                segments.append(.skip)
            } else if case .raw(let previous)? = segments.last {
                segments[segments.count - 1] = .raw(previous + ", " + token)
            } else {
                segments.append(.raw(token))
            }
        }
        return (segments, false)
    }

    private static func rpeLabel(_ rpe: Double) -> String {
        rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
    }
}
