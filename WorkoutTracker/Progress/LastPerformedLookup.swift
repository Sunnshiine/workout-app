import Foundation

struct LastPerformedLookupEntry: Equatable, Sendable {
    let resultText: String
    let sourceText: String
    let performedOn: Date
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

    func lookup(exerciseName: String, baseName: String) -> LastPerformedLookupEntry? {
        exactMatches[exerciseName] ?? fallbackMatches[baseName]
    }
}
