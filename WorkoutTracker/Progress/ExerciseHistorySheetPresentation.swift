import Foundation

/// The Exercise History sheet's presentation model (ADR-0012 data, ADR-0013 matching, `DESIGN.md`
/// §5.6 — the chip ledger).
///
/// Pure projection of the last ~5 Movement entries into Block-grouped, newest-first rows. All the
/// sheet's content-state rules live here so the view stays a dumb renderer: `Wn Dn` gutter labels
/// with Cadence, structured Sets carved into chips (load + muted RPE), and — kept out of the ledger
/// until asked — the row's `*` well collecting Skipped Sets, Legacy / Unstructured rawness (raw *as
/// entered*, best-effort parsed for its chips), and spelling-variant annotations. The athlete-summoned
/// total-volume chart is derived here too: one point per entry, weight × reps, flagged approximate
/// where Legacy Log rawness makes the total best-effort. Movement matching and the local fetch happen
/// upstream; this type only orders, caps, groups, annotates, and totals.
struct ExerciseHistorySheetPresentation: Equatable, Sendable {
    /// One carved chip — a single Logged Set split into its load (`27.5×10`) and muted RPE (`8`) so
    /// the view can tone them independently.
    struct Chip: Equatable, Sendable {
        let load: String
        let rpe: String?
    }

    /// One detail collected into the row's `*` well — the quiet content kept out of the chip ledger
    /// until the athlete taps the `*` (DESIGN.md §5.6). The view renders the well in the order the
    /// row lists them.
    enum Annotation: Equatable, Sendable {
        /// The entry's own entered base name when it differs beyond case from the viewed Exercise's
        /// (ADR-0013 fallback spelling) — the view shows it *as "…"*.
        case asName(String)
        /// One or more Sets were Skipped — never rendered as chips (DESIGN.md §5.6).
        case skipped(Int)
        /// Raw entered text (a Legacy Log or Unstructured Set Log) preserved verbatim, never
        /// normalized (ADR-0005) — the well shows it *as entered*.
        case asEntered(String)
    }

    /// One entry: a `Wn Dn` gutter with the entry's Cadence beneath, then its Sets as chips, plus any
    /// annotations hidden behind the `*` well.
    struct Row: Equatable, Sendable {
        let gutter: String
        let cadence: String?
        let chips: [Chip]
        let annotations: [Annotation]
        /// Whether the W/D label carries a `*` that expands into the carved well.
        var hasWell: Bool { !annotations.isEmpty }
    }

    /// Entries sharing a Block (sheet tab), newest Block first.
    struct Block: Equatable, Sendable {
        let header: String
        let rows: [Row]
    }

    /// One point on the athlete-summoned total-volume chart: weight × reps summed across the entry's
    /// parseable Sets.
    struct VolumePoint: Equatable, Sendable {
        let blockHeader: String
        let gutter: String
        let volume: Double
        /// Legacy Log rawness left the total best-effort — the chart draws a hollow `≈` dot rather
        /// than a solid one (DESIGN.md §5.6).
        let approximate: Bool
    }

    static let entryLimit = 5

    let title: String
    let subtitle: String
    let blocks: [Block]
    /// Total-volume points oldest-first (left→right on the chart, the reverse of the newest-first
    /// ledger). A dotted Block seam is drawn where consecutive points cross a `blockHeader` boundary.
    let volumePoints: [VolumePoint]
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

        let recent =
            entries
            .sorted { $0.performedOn > $1.performedOn }
            .prefix(Self.entryLimit)

        var order: [String] = []
        var grouped: [String: [Row]] = [:]
        var points: [VolumePoint] = []
        for entry in recent {
            let (header, gutter) = Self.splitSource(entry.source)
            let projected = Self.project(entry, gutter: gutter, header: header, anchorBaseName: anchorBaseName)
            if grouped[header] == nil { order.append(header) }
            grouped[header, default: []].append(projected.row)
            if let point = projected.volumePoint { points.append(point) }
        }

        blocks = order.map { Block(header: $0, rows: grouped[$0] ?? []) }
        // The chart reads oldest→newest, left→right — the reverse of the newest-first ledger.
        volumePoints = points.reversed()
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

    private static func project(
        _ entry: LastPerformedOccurrence,
        gutter: String,
        header: String,
        anchorBaseName: String
    ) -> (row: Row, volumePoint: VolumePoint?) {
        let cadence = splitCadence(entry.fullName).cadence
        let parsed = parse(entry.resultText)

        var annotations: [Annotation] = []
        if entry.baseName.lowercased() != anchorBaseName.lowercased() {
            annotations.append(.asName(entry.baseName))
        }
        if parsed.skipCount > 0 {
            annotations.append(.skipped(parsed.skipCount))
        }
        if let rawText = parsed.rawText {
            annotations.append(.asEntered(rawText))
        }

        let row = Row(gutter: gutter, cadence: cadence, chips: parsed.chips, annotations: annotations)

        // A total we could not compute at all (nothing parsed) is left off the chart rather than
        // plotted as a misleading zero.
        let volumePoint =
            parsed.chips.isEmpty
            ? nil
            : VolumePoint(
                blockHeader: header,
                gutter: gutter,
                volume: parsed.volume,
                approximate: parsed.rawText != nil
            )

        return (row, volumePoint)
    }

    /// The best-effort read of one entry's result text: carved chips, a Skipped-Set count, coalesced
    /// raw text for the well, and the total volume.
    private struct Parsed {
        var chips: [Chip]
        var skipCount: Int
        var rawText: String?
        var volume: Double
    }

    /// Splits a display string into carved chips, a Skipped-Set count, coalesced raw text, and the
    /// best-effort total volume.
    ///
    /// Every entry — structured, mixed, or a whole Legacy Log — is split on the extractor's `", "`
    /// separator and classified token-by-token: a structured Set Log becomes a chip and adds to the
    /// volume, a `skip` sentinel increments the count and is never a chip, and anything else is
    /// rawness that never enters the ledger. Raw fragments coalesce back with `", "` so the well
    /// shows them verbatim (ADR-0005 "never normalized"); the volume is best-effort whenever any
    /// rawness survived.
    private static func parse(_ resultText: String) -> Parsed {
        var chips: [Chip] = []
        var skipCount = 0
        var rawParts: [String] = []
        var volume = 0.0

        for token in resultText.components(separatedBy: ", ") {
            let classification = SetLogToken.classify(token)
            if let log = classification.setLog {
                chips.append(Chip(load: "\(log.weight.label)×\(log.reps)", rpe: rpeLabel(log.rpe)))
                if case .pounds(let pounds) = log.weight {
                    volume += pounds * Double(log.reps)
                }
            } else if classification.state == .skipped {
                skipCount += 1
            } else {
                rawParts.append(token)
            }
        }

        let rawText = rawParts.isEmpty ? nil : rawParts.joined(separator: ", ")
        return Parsed(chips: chips, skipCount: skipCount, rawText: rawText, volume: volume)
    }

    private static func rpeLabel(_ rpe: Double) -> String {
        rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
    }
}
