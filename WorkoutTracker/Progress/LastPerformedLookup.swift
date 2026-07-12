import Foundation

struct LastPerformedLookupEntry: Equatable, Sendable {
    let resultText: String
    let sourceText: String
    let performedOn: Date
    /// The matched entry's own entered name — non-nil only for a tier-3 (Movement-level)
    /// match, where the line labels itself *as "…"* because the history was logged under a
    /// differently-spelled name (ADR-0013).
    var matchedName: String?

    init(resultText: String, sourceText: String, performedOn: Date, matchedName: String? = nil) {
        self.resultText = resultText
        self.sourceText = sourceText
        self.performedOn = performedOn
        self.matchedName = matchedName
    }
}

struct LastPerformedLookupSnapshot: Equatable, Sendable {
    static let empty = LastPerformedLookupSnapshot()

    private let exactMatches: [String: LastPerformedLookupEntry]
    private let fallbackMatches: [String: LastPerformedLookupEntry]

    init(
        exactMatches: [String: LastPerformedLookupEntry] = [:],
        fallbackMatches: [String: LastPerformedLookupEntry] = [:]
    ) {
        self.exactMatches = exactMatches
        self.fallbackMatches = fallbackMatches
    }

    init(entries: [LastPerformedEntry]) {
        var exactMatches: [String: LastPerformedLookupEntry] = [:]
        var fallbackMatches: [String: LastPerformedLookupEntry] = [:]

        for entry in entries {
            let mappedEntry = LastPerformedLookupEntry(
                resultText: entry.displayResultText,
                sourceText: entry.source,
                performedOn: entry.performedOn
            )

            let existingExact = exactMatches[entry.fullName]
            if existingExact == nil || mappedEntry.performedOn >= existingExact?.performedOn ?? .distantPast {
                exactMatches[entry.fullName] = mappedEntry
            }

            let existingFallback = fallbackMatches[entry.baseName]
            if existingFallback == nil || mappedEntry.performedOn >= existingFallback?.performedOn ?? .distantPast {
                fallbackMatches[entry.baseName] = mappedEntry
            }
        }

        self.exactMatches = exactMatches
        self.fallbackMatches = fallbackMatches
    }

    /// The three-tier Last Performed ladder (ADR-0013), most comparable first:
    /// (1) exact full name including Cadence, (2) exact base name — both byte-identical to
    /// today — then (3) Movement level, firing only where the line would otherwise be blank.
    func lookup(exerciseName: String, baseName: String) -> LastPerformedLookupEntry? {
        if let exact = exactMatches[exerciseName] { return exact }
        if let fallback = fallbackMatches[baseName] { return fallback }
        return movementMatch(baseName: baseName)
    }

    /// Tier 3: canonicalize the anchor base name and fuzzy-compare it against the distinct
    /// base names on device (a few hundred at most), returning the newest matching entry
    /// annotated with its own entered name.
    private func movementMatch(baseName: String) -> LastPerformedLookupEntry? {
        var best: (entry: LastPerformedLookupEntry, name: String)?
        for (candidateName, entry) in fallbackMatches
        where MovementMatching.areSameMovement(baseName, candidateName) {
            if best == nil || entry.performedOn > best!.entry.performedOn {
                best = (entry, candidateName)
            }
        }
        guard let best else { return nil }
        return LastPerformedLookupEntry(
            resultText: best.entry.resultText,
            sourceText: best.entry.sourceText,
            performedOn: best.entry.performedOn,
            matchedName: best.name
        )
    }
}
