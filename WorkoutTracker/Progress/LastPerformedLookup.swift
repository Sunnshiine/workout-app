import Foundation

/// One resolved Last Performed line: the matched occurrence (PRD #330's canonical evidence) plus
/// the tier-3 annotation. `resultText` / `sourceText` / `performedOn` are read straight off the
/// occurrence — no parallel copy — so the display projection cannot drift from the stored evidence.
struct LastPerformedLookupEntry: Equatable, Sendable {
    /// The matched Last Performed occurrence.
    let occurrence: LastPerformedOccurrence
    /// The matched entry's own entered name — non-nil only for a tier-3 (Movement-level)
    /// match, where the line labels itself *as "…"* because the history was logged under a
    /// differently-spelled name (ADR-0013). A lookup-result concern, not a property of the
    /// occurrence itself.
    var matchedName: String?

    init(occurrence: LastPerformedOccurrence, matchedName: String? = nil) {
        self.occurrence = occurrence
        self.matchedName = matchedName
    }

    var resultText: String { occurrence.resultText }
    var sourceText: String { occurrence.source }
    var performedOn: Date { occurrence.performedOn }
}

struct LastPerformedLookupSnapshot: Equatable, Sendable {
    static let empty = LastPerformedLookupSnapshot()

    private let exactMatches: [String: LastPerformedOccurrence]
    private let fallbackMatches: [String: LastPerformedOccurrence]
    /// Every occurrence, retained whole so the Exercise History sheet can read the last ~5 entries
    /// for a Movement — the Last Performed line's dictionaries reduce to one-per-name and cannot.
    private let occurrences: [LastPerformedOccurrence]

    init(
        exactMatches: [String: LastPerformedOccurrence] = [:],
        fallbackMatches: [String: LastPerformedOccurrence] = [:],
        occurrences: [LastPerformedOccurrence] = []
    ) {
        self.exactMatches = exactMatches
        self.fallbackMatches = fallbackMatches
        self.occurrences = occurrences
    }

    init(entries: [LastPerformedEntry]) {
        let occurrences = entries.map(\.occurrence)
        var exactMatches: [String: LastPerformedOccurrence] = [:]
        var fallbackMatches: [String: LastPerformedOccurrence] = [:]
        for occurrence in occurrences {
            Self.keepingNewest(&exactMatches, occurrence.fullName, occurrence)
            Self.keepingNewest(&fallbackMatches, occurrence.baseName, occurrence)
        }
        self.init(exactMatches: exactMatches, fallbackMatches: fallbackMatches, occurrences: occurrences)
    }

    /// The recency dedup, stated once: within a key an occurrence replaces the incumbent unless the
    /// incumbent is strictly newer, so the newest Session for a name wins and ties resolve to the
    /// later occurrence in ingest order.
    private static func keepingNewest(
        _ matches: inout [String: LastPerformedOccurrence],
        _ key: String,
        _ occurrence: LastPerformedOccurrence
    ) {
        if let existing = matches[key], existing.performedOn > occurrence.performedOn { return }
        matches[key] = occurrence
    }

    /// The three-tier Last Performed ladder (ADR-0013), most comparable first:
    /// (1) exact full name including Cadence, (2) exact base name — both byte-identical to
    /// today — then (3) Movement level, firing only where the line would otherwise be blank.
    ///
    /// The base name is derived here by Cadence-stripping the exercise name, so callers pass only
    /// the exercise. This is the single owner of the two-tier rule (PRD #330).
    func lookup(for exerciseName: String) -> LastPerformedLookupEntry? {
        let baseName = splitCadence(exerciseName).base
        if let exact = exactMatches[exerciseName] { return LastPerformedLookupEntry(occurrence: exact) }
        if let fallback = fallbackMatches[baseName] { return LastPerformedLookupEntry(occurrence: fallback) }
        return movementMatch(baseName: baseName)
    }

    /// The Exercise History sheet's data source: every occurrence whose base name is the same
    /// Movement as the viewed Exercise (ADR-0013), newest first. The sheet always matches at
    /// Movement level regardless of which Last Performed tier produced the line. Fully offline — a
    /// filter over the in-memory snapshot, no fetch.
    func history(baseName: String) -> [LastPerformedOccurrence] {
        occurrences
            .filter { MovementMatching.areSameMovement(baseName, $0.baseName) }
            .sorted { $0.performedOn > $1.performedOn }
    }

    /// Tier 3: canonicalize the anchor base name and fuzzy-compare it against the distinct
    /// base names on device (a few hundred at most), returning the newest matching occurrence
    /// annotated with its own entered name.
    private func movementMatch(baseName: String) -> LastPerformedLookupEntry? {
        var best: LastPerformedOccurrence?
        for (candidateName, occurrence) in fallbackMatches
        where MovementMatching.areSameMovement(baseName, candidateName) {
            if best == nil || occurrence.performedOn > best!.performedOn {
                best = occurrence
            }
        }
        guard let best else { return nil }
        return LastPerformedLookupEntry(occurrence: best, matchedName: best.baseName)
    }
}
