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
    static let empty = LastPerformedLookupSnapshot(occurrences: [])

    private let exactMatches: [ExerciseName: LastPerformedOccurrence]
    private let fallbackMatches: [String: LastPerformedOccurrence]
    /// Every occurrence, retained whole so the Exercise History sheet can read the last ~5 entries
    /// for a Movement — the Last Performed line's dictionaries reduce to one-per-name and cannot.
    private let occurrences: [LastPerformedOccurrence]

    init(occurrences: [LastPerformedOccurrence]) {
        var exactMatches: [ExerciseName: LastPerformedOccurrence] = [:]
        var fallbackMatches: [String: LastPerformedOccurrence] = [:]
        for occurrence in occurrences {
            Self.keepingNewest(&exactMatches, occurrence.exerciseName, occurrence)
            Self.keepingNewest(&fallbackMatches, occurrence.exerciseName.base, occurrence)
        }
        self.exactMatches = exactMatches
        self.fallbackMatches = fallbackMatches
        self.occurrences = occurrences
    }

    init(entries: [LastPerformedEntry]) {
        self.init(occurrences: entries.map(\.occurrence))
    }

    func excluding(session: SessionCoordinate) -> LastPerformedLookupSnapshot {
        LastPerformedLookupSnapshot(occurrences: occurrences.filter { $0.source != session.storageValue })
    }

    /// The recency dedup, stated once: within a key an occurrence replaces the incumbent unless the
    /// incumbent is strictly newer, so the newest Session for a name wins and ties resolve to the
    /// later occurrence in ingest order.
    private static func keepingNewest<Key: Hashable>(
        _ matches: inout [Key: LastPerformedOccurrence],
        _ key: Key,
        _ occurrence: LastPerformedOccurrence
    ) {
        if let existing = matches[key], existing.performedOn > occurrence.performedOn { return }
        matches[key] = occurrence
    }

    /// The three-tier Last Performed ladder (ADR-0013), most comparable first:
    /// (1) the same Entered Name, Cadence included, (2) the same Base Name, then (3) the same
    /// Movement, firing only where the line would otherwise be blank. This is the single owner of
    /// the ladder (PRD #330).
    func lookup(for name: ExerciseName) -> LastPerformedLookupEntry? {
        if let exact = exactMatches[name] { return LastPerformedLookupEntry(occurrence: exact) }
        if let fallback = fallbackMatches[name.base] { return LastPerformedLookupEntry(occurrence: fallback) }
        return movementMatch(for: name)
    }

    /// The Exercise History sheet's data source: every occurrence that is the same Movement as the
    /// viewed Exercise (ADR-0013), newest first. The sheet always matches at
    /// Movement level regardless of which Last Performed tier produced the line. Fully offline — a
    /// filter over the in-memory snapshot, no fetch.
    func history(for name: ExerciseName) -> [LastPerformedOccurrence] {
        occurrences
            .filter { name.isSameMovement(as: $0.exerciseName) }
            .sorted { $0.performedOn > $1.performedOn }
    }

    /// Tier 3: compare the anchor against the newest occurrence of each distinct Base Name on
    /// device (a few hundred at most), returning the newest same-Movement occurrence annotated with
    /// its own name.
    private func movementMatch(for name: ExerciseName) -> LastPerformedLookupEntry? {
        var best: LastPerformedOccurrence?
        for occurrence in fallbackMatches.values where name.isSameMovement(as: occurrence.exerciseName) {
            if let best, occurrence.performedOn <= best.performedOn { continue }
            best = occurrence
        }
        guard let best else { return nil }
        return LastPerformedLookupEntry(occurrence: best, matchedName: best.exerciseName.base)
    }
}
