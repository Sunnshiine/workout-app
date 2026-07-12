import Foundation

/// One `exercise_history` entry projected into a plain value type for the sheet — no SwiftData,
/// so the sheet presentation model is unit-testable and `Sendable`. `resultText` is the entry's
/// `displayResultText` (structured Set Logs joined in Set order, or Legacy / Unstructured text as
/// entered); `source` is the `tab · Wn Dn` dedup key.
struct ExerciseHistoryEntry: Equatable, Sendable {
    let fullName: String
    let baseName: String
    let resultText: String
    let source: String
    let performedOn: Date
}

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

    var isEmpty: Bool { blocks.isEmpty }

    init(anchorBaseName: String, entries: [ExerciseHistoryEntry]) {
        title = anchorBaseName
        subtitle = "Exercise History · last \(Self.entryLimit)"

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

    private static func row(for entry: ExerciseHistoryEntry, gutter: String, anchorBaseName: String) -> Row {
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
    private static func segments(for resultText: String) -> (segments: [SetSegment], asEntered: Bool) {
        let tokens = resultText.components(separatedBy: ", ")
        let classifications = tokens.map { SetLogToken.classify($0) }
        let isSetBased = classifications.contains { $0.setLog != nil || $0.state == .skipped }

        guard isSetBased else {
            return ([.raw(resultText)], true)
        }

        let segments = zip(tokens, classifications).map { token, classification -> SetSegment in
            if let log = classification.setLog {
                return .log(load: "\(log.weight.label)×\(log.reps)", rpe: rpeLabel(log.rpe))
            }
            if classification.state == .skipped {
                return .skip
            }
            return .raw(token)
        }
        return (segments, false)
    }

    private static func rpeLabel(_ rpe: Double) -> String {
        rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
    }
}
